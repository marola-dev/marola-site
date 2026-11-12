-- | Static files from two roots, read-only. The URL path is checked against an allowlist before it
-- touches the disk, so no encoding trick has to be recognised: it is only never in the list.
module Marola.Server.Files (segments, resolve, contentType, cacheControl, handle, notFoundPage, docsRedirect) where

import Control.Monad (filterM)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAsciiLower, isAsciiUpper, isDigit, isHexDigit, toLower)
import Data.List (intercalate)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Marola.Server.Config (Config (..))
import Marola.Server.Http
import Network.HTTP.Types
import Network.Wai
import Numeric (showHex)
import System.Directory (doesFileExist, getFileSize, getModificationTime)
import System.FilePath (takeExtension, takeFileName, (</>))

safeChar :: Char -> Bool
safeChar c = isAsciiUpper c || isAsciiLower c || isDigit c || c == '.' || c == '-' || c == '_'

-- | Not empty, not hidden (no leading dot, which also rules out @.@ and @..@), at most 128 characters
-- of letters, digits, @.@, @-@ and @_@. That excludes @/@, @\\@, @%@, NUL and @:@.
safeSegment :: Text -> Bool
safeSegment s = not (T.null s) && T.head s /= '.' && T.length s <= 128 && T.all safeChar s

-- | The segments of a URL path, or 'Nothing' if the path could leave the roots or reach a hidden
-- file. A path that ends in @/@ names the @index.html@ of that folder. The one hidden name allowed is
-- a first segment @.well-known@ (RFC 8615); everything under it must be as plain as any other.
segments :: Text -> Maybe [Text]
segments p
  | T.null p || T.head p /= '/' || T.length p > 512 = Nothing
  | otherwise =
      let parts0 = T.splitOn "/" (T.drop 1 p)
          parts = if last parts0 == "" then init parts0 <> ["index.html"] else parts0
          checkable = case parts of
            (".well-known" : rest) | not (null rest) -> rest
            _ -> parts
       in if all safeSegment checkable then Just parts else Nothing

under :: FilePath -> [Text] -> FilePath
under root parts = root </> intercalate "/" (map T.unpack parts)

-- | @/data/<x>@ is the board data folder's first, so a deploy can replace the boards without
-- rebuilding the page; the page's own @data/@ (fixtures) is the fallback.
candidates :: Config -> [Text] -> [FilePath]
candidates cfg = \case
  parts@("data" : rest) | not (null rest) -> [under cfg.dataDir rest, under cfg.static parts]
  parts -> [under cfg.static parts]

-- | The file to send for a path: the file itself, else @<path>.html@. A folder is never listed.
resolve :: Config -> Text -> IO (Maybe FilePath)
resolve cfg p = case segments p of
  Nothing -> pure Nothing
  Just parts -> do
    let withHtml = case reverse parts of
          (lastSeg : before) | not ("." `T.isInfixOf` lastSeg) -> [reverse ((lastSeg <> ".html") : before)]
          _ -> []
    found <- filterM doesFileExist (concatMap (candidates cfg) (parts : withHtml))
    pure (case found of (f : _) -> Just f; [] -> Nothing)

contentType :: FilePath -> ByteString
contentType file = case map toLower (takeExtension file) of
  ".html" -> "text/html; charset=utf-8"
  ".js" -> "text/javascript; charset=utf-8"
  ".mjs" -> "text/javascript; charset=utf-8"
  ".css" -> "text/css; charset=utf-8"
  ".json" -> "application/json; charset=utf-8"
  ".txt" -> "text/plain; charset=utf-8"
  ".md" -> "text/plain; charset=utf-8"
  ".xml" -> "application/xml; charset=utf-8"
  ".svg" -> "image/svg+xml"
  ".png" -> "image/png"
  ".jpg" -> "image/jpeg"
  ".jpeg" -> "image/jpeg"
  ".webp" -> "image/webp"
  ".ico" -> "image/x-icon"
  ".woff2" -> "font/woff2"
  ".woff" -> "font/woff"
  ".mp3" -> "audio/mpeg"
  _ -> "application/octet-stream"

-- | @name.<8 or more hex digits>.ext@: the file name carries its content hash, so it never changes.
hashed :: String -> Bool
hashed name = case reverse (splitOn '.' name) of
  (ext : h : _ : _) -> not (null ext) && all (\c -> isAsciiLower c || isDigit c) ext && length h >= 8 && all (\c -> isHexDigit c && not (isAsciiUpper c)) h
  _ -> False
  where
    splitOn ch s = case break (== ch) s of
      (a, []) -> [a]
      (a, _ : rest) -> a : splitOn ch rest

cacheControl :: FilePath -> ByteString
cacheControl file
  | hashed name = "public, max-age=31536000, immutable"
  | map toLower (takeExtension name) `elem` [".woff2", ".woff", ".png", ".jpg", ".jpeg", ".webp", ".ico", ".svg"] = "public, max-age=86400"
  | otherwise = "no-cache"
  where
    name = takeFileName file

-- | The 404 page of the language the path is under, sent with status 404. A build without pages has
-- none, and the plain text answers.
notFoundPage :: Config -> Text -> IO Response
notFoundPage cfg p = do
  let file = if "/en/" `T.isPrefixOf` p then cfg.static </> "en" </> "404.html" else cfg.static </> "404.html"
  exists <- doesFileExist file
  if exists
    then do
      body <- BL.readFile file
      pure (responseLBS status404 [(hContentType, "text/html; charset=utf-8")] body)
    else pure (plain status404 "not found\n")

-- | The docs moved to docs.marola.dev (MIP-0070 §5.8); the legacy 404 page forwarded @/docs/*@ with
-- a script, which the CSP forbids here. The host is fixed and the path must be plain URL characters,
-- so the redirect cannot be pointed anywhere else.
docsRedirect :: Request -> Maybe Response
docsRedirect req
  | path == "/docs" || "/docs/" `BS.isPrefixOf` path,
    BC.all (\c -> c == '/' || c == '%' || c == '~' || safeChar c) path,
    not (".." `T.isInfixOf` decodedPath req) =
      Just (responseLBS status301 [(hLocation, "https://docs.marola.dev/" <> BS.drop 6 path <> rawQueryString req), (hCacheControl, "public, max-age=3600")] "")
  | otherwise = Nothing
  where
    path = rawPathInfo req

-- | GET and HEAD only, with an ETag of size plus mtime (cheap, and it changes with every deploy)
-- and @Last-Modified@, answered with a 304 when the client has them.
handle :: Config -> Request -> IO Response
handle cfg req
  | requestMethod req `notElem` [methodGet, methodHead] =
      pure (responseLBS status405 [(hContentType, "text/plain; charset=utf-8"), ("Allow", "GET, HEAD")] "method not allowed\n")
  | otherwise = do
      let p = decodedPath req
      found <- resolve cfg p
      case found of
        Nothing -> maybe (notFoundPage cfg p) pure (docsRedirect req)
        Just file -> do
          size <- getFileSize file
          modified <- getModificationTime file
          let seconds = floor (utcTimeToPOSIXSeconds modified) :: Integer
              etag = BC.pack ("\"" <> showHex size "" <> "-" <> showHex seconds "" <> "\"")
              lastModified = BC.pack (formatTime defaultTimeLocale "%a, %d %b %Y %H:%M:%S GMT" modified)
              common = [("ETag", etag), (hLastModified, lastModified), (hCacheControl, cacheControl file)]
              inm = lookup hIfNoneMatch (requestHeaders req)
              ims = lookup hIfModifiedSince (requestHeaders req)
              notModified = case inm of
                Just v -> etag `elem` map BC.strip (BC.split ',' v) || BC.strip v == "*"
                Nothing -> maybe False (== lastModified) ims
          pure $
            if notModified
              then responseLBS status304 common ""
              else responseFile status200 ((hContentType, contentType file) : common) file Nothing
