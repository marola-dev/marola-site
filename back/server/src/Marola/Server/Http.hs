-- | What every handler shares: the environment, request helpers and plain responses.
module Marola.Server.Http
  ( Env (..),
    Logger,
    Level (..),
    GithubRequest (..),
    GithubHttp,
    BodyTooLarge (..),
    plain,
    html,
    jsonResponse,
    redirect303,
    header,
    queryText,
    cookie,
    decodedPath,
    readBodyLimited,
    readForm,
    FormError (..),
    isContentType,
    tshow,
    Route (..),
    Params,
    matchRoute,
    languageOf,
  )
where

import Control.Exception (Exception, throwIO)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.CaseInsensitive qualified as CI
import Data.IORef
import Data.Int (Int64)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time (UTCTime)
import Marola.Layout (Catalog, Language (..))
import Marola.Server.Config (Config)
import Marola.Server.RateLimit (Window)
import Network.HTTP.Types
import Network.Wai

data Level = Information | Warning | Error deriving (Eq, Show)

-- | Category, level, message. The message never holds an address, a query, a body or a secret.
type Logger = Text -> Level -> Text -> IO ()

data GithubRequest = GithubRequest
  { method :: ByteString,
    url :: Text,
    headers :: [Header],
    body :: ByteString
  }

-- | The two GitHub calls go through this, so a test swaps in a fake GitHub. Status and body.
type GithubHttp = GithubRequest -> IO (Int, ByteString)

data Env = Env
  { config :: Config,
    clock :: IO UTCTime,
    github :: GithubHttp,
    logger :: Logger,
    csrfKey :: ByteString,
    catalog :: Catalog,
    keyRates :: Window Text,
    general :: Window String,
    strict :: Window String
  }

tshow :: (Show a) => a -> Text
tshow = T.pack . show

plain :: Status -> Text -> Response
plain st t = responseLBS st [(hContentType, "text/plain; charset=utf-8")] (BL.fromStrict (TE.encodeUtf8 t))

html :: Status -> ByteString -> Text -> Response
html st cache t =
  responseLBS st [(hContentType, "text/html; charset=utf-8"), (hCacheControl, cache)] (BL.fromStrict (TE.encodeUtf8 t))

jsonResponse :: Status -> ByteString -> BL.ByteString -> [Header] -> Response
jsonResponse st cache body extra =
  responseLBS st ([(hContentType, "application/json; charset=utf-8"), (hCacheControl, cache)] <> extra) body

redirect303 :: ByteString -> [Header] -> Response
redirect303 location extra = responseLBS status303 ([(hLocation, location), (hCacheControl, "no-store")] <> extra) ""

header :: Request -> HeaderName -> Text
header req n = maybe "" (TE.decodeUtf8With lenientDecode) (lookup n (requestHeaders req))

-- | The first value of a query parameter, "" when it is missing.
queryText :: Request -> ByteString -> Text
queryText req n = case lookup n (queryString req) of
  Just (Just v) -> TE.decodeUtf8With lenientDecode v
  _ -> ""

-- | A cookie of the request, by name.
cookie :: Request -> ByteString -> Maybe Text
cookie req name =
  let pairs =
        [ (BC.strip k, BC.strip (BS.drop 1 v))
        | raw <- [v | (n, v) <- requestHeaders req, n == "Cookie"],
          part <- BC.split ';' raw,
          let (k, v) = BC.break (== '=') part
        ]
   in TE.decodeUtf8With lenientDecode <$> lookup name pairs

-- | The request path: percent-decoded, except an encoded @/@,
-- which stays @%2F@ so it can never split a segment. Invalid UTF-8 keeps its escapes.
decodedPath :: Request -> Text
decodedPath req =
  let raw = rawPathInfo req
      go acc b = case BS.uncons b of
        Nothing -> BS.pack (reverse acc)
        Just (37, rest)
          | BS.length rest >= 2,
            Just hi <- hex (BS.index rest 0),
            Just lo <- hex (BS.index rest 1),
            hi * 16 + lo /= 47 ->
              go (fromIntegral (hi * 16 + lo) : acc) (BS.drop 2 rest)
          | BS.length rest >= 2 && BS.take 2 rest `elem` ["2f", "2F"] -> go (map (fromIntegral . fromEnum) (reverse "%2F") <> acc) (BS.drop 2 rest)
        Just (c, rest) -> go (c : acc) rest
      hex w
        | w >= 48 && w <= 57 = Just (fromIntegral w - 48 :: Int)
        | w >= 97 && w <= 102 = Just (fromIntegral w - 87)
        | w >= 65 && w <= 70 = Just (fromIntegral w - 55)
        | otherwise = Nothing
      decoded = go [] raw
   in case TE.decodeUtf8' decoded of
        Right t -> t
        Left _ -> TE.decodeUtf8With lenientDecode raw

data BodyTooLarge = BodyTooLarge deriving (Show)

instance Exception BodyTooLarge

-- | The whole body, refused with 'BodyTooLarge' past @limit@ bytes while it streams.
readBodyLimited :: Int64 -> Request -> IO ByteString
readBodyLimited limit req = do
  acc <- newIORef (0 :: Int64, [])
  let loop = do
        chunk <- getRequestBodyChunk req
        if BS.null chunk
          then pure ()
          else do
            (n, cs) <- readIORef acc
            let n' = n + fromIntegral (BS.length chunk)
            if n' > limit then throwIO BodyTooLarge else writeIORef acc (n', chunk : cs) >> loop
  loop
  BS.concat . reverse . snd <$> readIORef acc

isContentType :: Request -> ByteString -> Bool
isContentType req prefix = case lookup hContentType (requestHeaders req) of
  Just v -> CI.foldCase prefix `BS.isPrefixOf` CI.foldCase v
  Nothing -> False

data FormError = NotAForm | BadForm Int deriving (Eq, Show)

-- | A urlencoded body: at most 20 values of at most 8000 characters
-- (a message is at most 4000: a field of 8000 is already an abuse), in a body of at most 1 MB.
readForm :: Request -> IO (Either FormError (Map.Map Text Text))
readForm req
  | not (isContentType req "application/x-www-form-urlencoded") = pure (Left NotAForm)
  | otherwise = do
      body <- readBodyLimited 1048576 req
      let pairs = [(TE.decodeUtf8With lenientDecode k, TE.decodeUtf8With lenientDecode v) | (k, v) <- parseSimpleQuery body]
      pure $
        if length pairs > 20 || any ((> 8000) . T.length . snd) pairs
          then Left (BadForm 400)
          else Right (Map.fromListWith (\new old -> old <> "," <> new) pairs)

type Params = Map.Map Text Text

-- | An endpoint: a method, a pattern of literal segments and @{name}@
-- parameters, and whether the strict rate limit applies.
data Route = Route
  { method :: Method,
    pattern :: Text,
    strict :: Bool,
    run :: Env -> Request -> Params -> IO Response
  }

-- | The parameters when @path@ (as 'decodedPath' gives it) matches @pattern@. Literal segments compare
-- without case, a parameter takes one non-empty segment, and one trailing slash is ignored.
matchRoute :: Text -> Text -> Maybe Params
matchRoute pat path =
  let segs t = case T.splitOn "/" t of
        "" : rest -> Just (if not (null rest) && last rest == "" && length rest > 1 then init rest else rest)
        _ -> Nothing
      go acc (p : ps) (x : xs)
        | Just name <- T.stripPrefix "{" p >>= T.stripSuffix "}" = if T.null x then Nothing else go (Map.insert name x acc) ps xs
        | T.toCaseFold p == T.toCaseFold x = go acc ps xs
        | otherwise = Nothing
      go acc [] [] = Just acc
      go _ _ _ = Nothing
   in do
        ps <- segs pat
        xs <- segs path
        go Map.empty ps xs

-- | @/en@ and everything under it, segment by segment, is English (@/english@ is not).
languageOf :: Text -> Language
languageOf path =
  let l = T.toCaseFold path
   in if l == "/en" || "/en/" `T.isPrefixOf` l then En else PtBr
