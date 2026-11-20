-- | The base map's tiles: @/tiles/<name>.pmtiles@, one file read by byte range (the PMTiles
-- protocol asks for a few kilobytes at a time out of some hundred megabytes). The only route that
-- answers a @Range@; every other file is sent whole ('Marola.Server.App.streamFile').
module Marola.Server.Tiles (prefix, permits, archive, Range (..), rangeOf, handle) where

import Control.Monad (filterM)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder (byteString)
import Data.ByteString.Char8 qualified as BC
import Data.Char (isAsciiLower, isDigit)
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
import System.FilePath ((</>))
import System.IO (IOMode (ReadMode), SeekMode (AbsoluteSeek), hSeek, withBinaryFile)

prefix :: Text
prefix = "/tiles/"

-- | Requests a minute per client, in a window of its own: a map that is dragged across three zoom
-- levels asks for hundreds of tiles, which the general limit would refuse.
permits :: Int
permits = 6000

-- | The file name a path asks for: @/tiles/<1 to 64 of a-z, 0-9 and ->.pmtiles@ and nothing else,
-- so the name can hold no separator, no dot of its own and no escape.
archive :: Text -> Maybe FilePath
archive p = do
  name <- T.stripPrefix prefix p >>= T.stripSuffix ".pmtiles"
  if not (T.null name) && T.length name <= 64 && T.all (\c -> isAsciiLower c || isDigit c || c == '-') name
    then Just (T.unpack name <> ".pmtiles")
    else Nothing

data Range
  = Whole
  | -- | First and last byte, both inside the file.
    Part Integer Integer
  | Unsatisfiable
  deriving (Eq, Show)

-- | The one range of a @Range@ header for a file of @size@ bytes. Another unit is ignored, as RFC
-- 9110 says. A list of ranges is refused: the answer would be a multipart body nobody here needs.
rangeOf :: Integer -> Maybe ByteString -> Range
rangeOf size = \case
  Nothing -> Whole
  Just raw -> case BS.stripPrefix "bytes=" (BC.strip raw) of
    Nothing -> Whole
    Just spec -> case BC.break (== '-') (BC.strip spec) of
      (a, rest) | Just b <- BS.stripPrefix "-" rest -> case (BS.null a, BS.null b, number a, number b) of
        (False, True, Just first, _) | first < size -> Part first (size - 1)
        (False, False, Just first, Just lastByte) | first <= lastByte, first < size -> Part first (min lastByte (size - 1))
        (True, False, _, Just suffix) | suffix > 0, size > 0 -> Part (max 0 (size - suffix)) (size - 1)
        _ -> Unsatisfiable
      _ -> Unsatisfiable
  where
    number s
      | BS.length s <= 18 && BC.all isDigit s = Just (if BS.null s then 0 else read (BC.unpack s) :: Integer)
      | otherwise = Nothing

-- | The tiles folder first, then the page's own @tiles/@ (the fixture of an offline build), as
-- @/data/@ does.
find :: Config -> FilePath -> IO (Maybe FilePath)
find cfg name = do
  found <- filterM doesFileExist [cfg.tiles </> name, cfg.static </> "tiles" </> name]
  pure (case found of (f : _) -> Just f; [] -> Nothing)

-- | GET and HEAD. The ETag is size plus mtime: a new file on the host changes it, which is how the
-- PMTiles client notices that the ranges it cached belong to the old one.
handle :: Config -> Request -> IO Response
handle cfg req
  | requestMethod req `notElem` [methodGet, methodHead] =
      pure (responseLBS status405 [(hContentType, "text/plain; charset=utf-8"), ("Allow", "GET, HEAD")] "method not allowed\n")
  | otherwise = case archive (decodedPath req) of
      Nothing -> pure missing
      Just name ->
        find cfg name >>= \case
          Nothing -> pure missing
          Just file -> do
            size <- getFileSize file
            modified <- getModificationTime file
            let seconds = floor (utcTimeToPOSIXSeconds modified) :: Integer
                etag = BC.pack ("\"" <> showHex size "" <> "-" <> showHex seconds "" <> "\"")
                lastModified = BC.pack (formatTime defaultTimeLocale "%a, %d %b %Y %H:%M:%S GMT" modified)
                common = [("ETag", etag), (hLastModified, lastModified), (hCacheControl, "public, max-age=86400"), ("Accept-Ranges", "bytes")]
                typed = (hContentType, "application/octet-stream") : common
                asked = lookup hIfNoneMatch (requestHeaders req)
                notModified = case asked of
                  Just v -> etag `elem` map BC.strip (BC.split ',' v) || BC.strip v == "*"
                  Nothing -> lookup hIfModifiedSince (requestHeaders req) == Just lastModified
                -- A range made against another version of the file gets the whole new one.
                current = maybe True ((`elem` [etag, lastModified]) . BC.strip) (lookup hIfRange (requestHeaders req))
                range = if current then rangeOf size (lookup hRange (requestHeaders req)) else Whole
                len n = (hContentLength, BC.pack (show n))
            pure $
              if notModified
                then responseLBS status304 common ""
                else case range of
                  Whole -> responseStream status200 (len size : typed) (stream file 0 size)
                  Part first lastByte ->
                    let contentRange = BC.pack ("bytes " <> show first <> "-" <> show lastByte <> "/" <> show size)
                     in responseStream status206 (len (lastByte - first + 1) : ("Content-Range", contentRange) : typed) (stream file first (lastByte - first + 1))
                  Unsatisfiable -> responseLBS status416 (("Content-Range", BC.pack ("bytes */" <> show size)) : (hContentType, "text/plain; charset=utf-8") : common) "range not satisfiable\n"
  where
    missing = plain status404 "not found\n"

stream :: FilePath -> Integer -> Integer -> StreamingBody
stream file offset count write flush = withBinaryFile file ReadMode $ \h -> do
  hSeek h AbsoluteSeek offset
  let loop left
        | left <= 0 = flush
        | otherwise = do
            chunk <- BS.hGetSome h (fromIntegral (min 65536 left))
            if BS.null chunk then flush else write (byteString chunk) >> loop (left - fromIntegral (BS.length chunk))
  loop count
