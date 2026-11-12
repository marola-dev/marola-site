-- | The pipeline, in this order: security headers, the request log, the
-- exception handler, compression, the rate limits, the body guard, the routes and the static files.
module Marola.Server.App
  ( bodyLimit,
    generalPermits,
    strictPermits,
    newEnv,
    jsonLogger,
    routes,
    application,
    applicationWith,
  )
where

import Codec.Compression.Brotli qualified as Brotli
import Codec.Compression.GZip qualified as GZip
import Control.Concurrent.MVar
import Control.Exception (SomeException, displayException, fromException, throwIO, try)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder (byteString, toLazyByteString)
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.CaseInsensitive qualified as CI
import Data.IORef
import Data.Int (Int64)
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, mapMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Typeable (typeOf)
import Marola.Json
import Marola.Layout qualified as Layout
import Marola.Server.Config (Config (..))
import Marola.Server.Contact qualified as Contact
import Marola.Server.Files qualified as Files
import Marola.Server.Github qualified as Github
import Marola.Server.Http
import Marola.Server.OpenApi qualified as OpenApi
import Marola.Server.RateLimit qualified as RateLimit
import Marola.Server.Security qualified as Security
import Marola.Server.Session qualified as Session
import Marola.Server.Store (utc)
import Marola.Server.Store qualified as Store
import Marola.Server.StudyApi qualified as StudyApi
import Marola.Server.StudyStore qualified as StudyStore
import Marola.Server.Web qualified as Web
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Internal (Response (..))
import System.Directory (getFileSize)
import System.FilePath ((</>))
import System.IO (IOMode (ReadMode), hFlush, stdout, withBinaryFile)

-- | Every request body: 1 MB, except the study upload ('StudyApi.uploadLimit').
bodyLimit :: Int64
bodyLimit = 1048576

-- | A page load fetches a few dozen files, so the general limit is wide; it stops a flood, not a
-- visitor. The strict one is for the POST endpoints and the login: 10 in 10 minutes per client.
generalPermits, strictPermits :: Int
generalPermits = 300
strictPermits = 10

-- | One JSON object per line on stdout.
jsonLogger :: IO Logger
jsonLogger = do
  lock <- newMVar ()
  pure $ \category level message -> do
    now <- getCurrentTime
    let line =
          renderText
            ( JObject
                [ ("Timestamp", JString (utc now <> " ")),
                  ("EventId", JInt 0),
                  ("LogLevel", JString (tshow level)),
                  ("Category", JString category),
                  ("Message", JString message)
                ]
            )
    withMVar lock $ \_ -> TIO.putStrLn line >> hFlush stdout

-- | Creates the database and the CSRF key, reads the page catalogs and makes the rate windows.
newEnv :: Config -> IO UTCTime -> GithubHttp -> Logger -> IO Env
newEnv config clock github logger = do
  Store.init config.db
  StudyStore.migrate config.db
  key <- Session.loadKey config.db
  catalog <- Layout.loadCatalog (config.static </> "i18n")
  cat <- either (\e -> fail ("the page catalogs are missing under MAROLA_STATIC/i18n: " <> e)) pure catalog
  keyRates <- RateLimit.newWindow StudyApi.perKeyUnits StudyApi.keyWindow
  general <- RateLimit.newWindow generalPermits 60
  strict <- RateLimit.newWindow strictPermits 600
  pure Env {config = config, clock = clock, github = github, logger = logger, csrfKey = key, catalog = cat, keyRates = keyRates, general = general, strict = strict}

-- | Every endpoint; a request that matches none goes to the static files.
routes :: [Route]
routes =
  [ Route "POST" "/contact" True (\env req _ -> Contact.handle env req),
    Route "POST" "/en/contact" True (\env req _ -> Contact.handle env req),
    Route "POST" StudyApi.apiPath False (\env req _ -> StudyApi.submit env req),
    Route "GET" StudyApi.apiPath False (\env req _ -> StudyApi.list env req),
    Route "GET" (StudyApi.apiPath <> "/{id}") False (\env _ p -> StudyApi.one env (maybe "" id (lookupParam "id" p))),
    Route "GET" "/api/v1/skill.md" False (\_ _ _ -> pure StudyApi.skillResponse),
    Route "GET" OpenApi.path False (\_ _ _ -> pure OpenApi.response),
    Route "GET" Github.loginPath True (\env req _ -> Github.login env req),
    Route "GET" Github.callbackPath True (\env req _ -> Github.callback env req)
  ]
    <> Web.routes
  where
    lookupParam = Map.lookup

-- | The text types that are compressed.
textTypes :: [ByteString]
textTypes = ["text/html", "text/css", "text/plain", "text/javascript", "application/json", "application/xml", "image/svg+xml"]

data Coding = Br | Gzip deriving (Eq)

-- | The coding: the highest quality the client accepts, brotli on a tie.
chooseCoding :: ByteString -> Maybe Coding
chooseCoding accept =
  let items =
        [ (CI.foldCase (BC.strip name), q)
        | part <- BC.split ',' accept,
          (name : params) <- [BC.split ';' part],
          let q = case mapMaybe quality params of
                (x : _) -> x
                [] -> 1
        ]
      quality p = case BC.break (== '=') (BC.strip p) of
        (k, v) | CI.foldCase (BC.strip k) == "q" -> readQ (BC.strip (BS.drop 1 v))
        _ -> Nothing
      readQ v = case reads (BC.unpack (if "." `BS.isPrefixOf` v then "0" <> v else v)) :: [(Double, String)] of
        [(d, "")] -> Just d
        _ -> Nothing
      score c n = case [q | (name, q) <- items, name == n || name == "*", q > 0] of
        [] -> Nothing
        qs -> Just (maximum qs, c)
      candidates = mapMaybe id [score Br "br", score Gzip "gzip"]
   in case candidates of
        [] -> Nothing
        _ -> let best = maximum (map fst candidates) in snd <$> find ((== best) . fst) candidates

mimeOf :: [Header] -> ByteString
mimeOf hs = maybe "" (CI.foldCase . BC.strip . BC.takeWhile (/= ';')) (lookup hContentType hs)

compression :: Middleware
compression app req respond =
  case lookup hAcceptEncoding (requestHeaders req) of
    Just accept
      | not (BC.null (BC.strip accept)) -> app req $ \res -> do
          let hs = responseHeaders res
              compressible =
                mimeOf hs `elem` textTypes
                  && isJustNot (lookup hContentEncoding hs)
                  && isJustNot (lookup "Content-Range" hs)
                  && requestMethod req /= methodHead
                  && statusCode (responseStatus res) `notElem` [204, 304]
          if not compressible
            then respond res
            else do
              let vary = (hVary, "Accept-Encoding")
              case chooseCoding accept of
                Nothing -> respond (mapResponseHeaders (<> [vary]) res)
                Just coding -> do
                  body <- bodyOf res
                  let (name, packed) = case coding of
                        Br -> ("br", Brotli.compressWith Brotli.defaultCompressParams {Brotli.compressLevel = Brotli.CompressionLevel1} body)
                        Gzip -> ("gzip", GZip.compressWith GZip.defaultCompressParams {GZip.compressLevel = GZip.bestSpeed} body)
                      hs' = [h | h@(n, _) <- hs, n /= hContentLength] <> [vary, (hContentEncoding, name)]
                  respond (responseLBS (responseStatus res) hs' packed)
    _ -> app req respond
  where
    isJustNot = not . isJust

-- | The whole body of a response, for the compressor. Only the text types come here.
bodyOf :: Response -> IO BL.ByteString
bodyOf res = do
  let (_, _, withBody) = responseToStream res
  acc <- newIORef mempty
  withBody $ \stream -> stream (\b -> modifyIORef' acc (<> b)) (pure ())
  toLazyByteString <$> readIORef acc

tooMany :: Int -> Response
tooMany retry = responseLBS status429 [(hContentType, "text/plain; charset=utf-8"), ("Retry-After", BC.pack (show retry))] "too many requests\n"

payloadTooLarge :: Response
payloadTooLarge = plain status413 "payload too large\n"

-- | Whether this request is the study upload, which has its own body limit.
isUpload :: Request -> Bool
isUpload req = requestMethod req == methodPost && rawPathInfo req `elem` [TE.encodeUtf8 StudyApi.apiPath, "/submit", "/en/submit"]

-- | Refuses a declared body over the limit, and stops a body that grows over it while it streams.
bodyGuard :: Request -> IO (Either Response Request)
bodyGuard req = do
  let upload = isUpload req
      limit = if upload then StudyApi.uploadLimit else bodyLimit
      declared = case requestBodyLength req of
        KnownLength n -> fromIntegral n
        ChunkedBody -> 0
  if declared > limit
    then pure (Left (if upload then StudyApi.tooLarge else payloadTooLarge))
    else do
      seen <- newIORef (0 :: Int64)
      let next = do
            chunk <- getRequestBodyChunk req
            n <- atomicModifyIORef' seen (\s -> let s' = s + fromIntegral (BS.length chunk) in (s', s'))
            if n > limit then throwBody else pure chunk
      pure (Right (setRequestBodyChunks next req))
  where
    throwBody = throwIO BodyTooLarge

-- | A file as a plain stream: Warp would add @Accept-Ranges@ and answer ranges, which the site
-- never offered.
streamFile :: Response -> IO Response
streamFile res = case res of
  ResponseFile st hs path Nothing -> do
    size <- getFileSize path
    pure $ responseStream st ((hContentLength, BC.pack (show size)) : hs) $ \write flush -> withBinaryFile path ReadMode $ \h ->
      let loop = do
            chunk <- BS.hGetSome h 65536
            if BS.null chunk then flush else write (byteString chunk) >> loop
       in loop
  _ -> pure res

-- | The reason phrase the site has always sent, which differs from http-types' for a few codes.
reason :: Int -> Status
reason = \case
  413 -> mkStatus 413 "Payload Too Large"
  507 -> mkStatus 507 "Insufficient Storage"
  c -> toEnum c

-- | The application. @env@ holds the clock, the GitHub client and the logger, so a test swaps them.
application :: Env -> Application
application = applicationWith []

-- | The application with @extra@ routes before the others, for a test that needs one (a handler that throws).
applicationWith :: [Route] -> Env -> Application
applicationWith extra env req respond = do
  started <- getPOSIXTime
  let path = decodedPath req
      logLine st = do
        done <- getPOSIXTime
        let ms = realToFrac (done - started) * 1000 :: Double
        env.logger "Marola.Request" Information (TE.decodeUtf8Lenient (requestMethod req) <> " " <> T.take 200 path <> " " <> tshow st <> " " <> tshow ms)
      send res = do
        res' <- streamFile res
        r <- respond (mapResponseStatus (reason . statusCode) (mapResponseHeaders Security.addHeaders res'))
        logLine (statusCode (responseStatus res))
        pure r
  outcome <- try (compression (inner path) req send)
  case outcome of
    Right r -> pure r
    Left (e :: SomeException) -> case fromException e of
      Just BodyTooLarge -> send (if isUpload req then StudyApi.tooLarge else payloadTooLarge)
      Nothing -> do
        -- No detail and no stack trace to the client; the exception goes to the log.
        env.logger "Marola.Server" Error ("unhandled exception " <> T.pack (show (typeOf e)) <> ": " <> T.take 500 (T.pack (displayException e)))
        send (plain status500 "internal server error\n")
  where
    inner path rq k = do
      now <- env.clock
      let key = Security.requestKey rq
          matched = find (\r -> r.method == requestMethod rq && isJust (matchRoute r.pattern path)) (extra <> routes)
      general <- RateLimit.take env.general key 1 now
      case general of
        Left _ -> k (tooMany 60)
        Right () -> do
          strictOk <- case matched of
            Just r | r.strict -> RateLimit.take env.strict key 1 now
            _ -> pure (Right ())
          case strictOk of
            Left _ -> k (tooMany 600)
            Right () -> do
              guarded <- bodyGuard rq
              case guarded of
                Left res -> k res
                Right rq' -> case matched of
                  Just r | Just params <- matchRoute r.pattern path -> r.run env rq' params >>= k
                  _ -> Files.handle env.config rq' >>= k
