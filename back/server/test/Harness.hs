-- | A site for the tests: the real pipeline, in memory, over a temporary tree, with a clock the test
-- moves, a fake GitHub and the log kept.
module Harness
  ( Site (..),
    Req (..),
    Res (..),
    withSite,
    withSiteWith,
    get,
    post,
    send,
    header,
    bodyText,
    cookies,
    setCookieHeader,
    formBody,
    contactPost,
    goodForm,
    bulk,
    secret,
    fakeClientSecret,
    advance,
    logLines,
    start,
    write,
    tempDir,
    withDb,
    account,
    submission,
    hashOf,
    now0,
    bareConfig,
    lines',
    pdfBytes,
    validPdf,
    sha,
    latin1,
    Part (..),
    field,
    multipart,
    studyBody,
    jsonOf,
    jpath,
    jtext,
    errorCodes,
    filesUnder,
  )
where

import Control.Exception (bracket)
import Crypto.Hash (Digest, SHA256, hash)
import Data.Aeson qualified as A
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder (toLazyByteString)
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Foldable (toList)
import Data.IORef
import Data.IP (IP (..), toHostAddress, toHostAddress6)
import Data.Int (Int64)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (NominalDiffTime, UTCTime (..), addUTCTime, fromGregorian)
import Marola.Server.App qualified as App
import Marola.Server.Config (Config (..))
import Marola.Server.Http (Env, GithubRequest (..), Level, Route)
import Marola.Server.Store qualified as Store
import Marola.Server.StudyStore (Account (..))
import Marola.Server.StudyStore qualified as StudyStore
import Marola.Study
import Network.HTTP.Types
import Network.HTTP.Types.URI (renderSimpleQuery)
import Network.Socket (SockAddr (..))
import Network.Wai
import Network.Wai.Internal (ResponseReceived (..))
import Network.Wai.Test (setPath)
import System.Directory
import System.FilePath (takeDirectory, (</>))

data Site = Site
  { env :: Env,
    root :: FilePath,
    config :: Config,
    logs :: IORef [Text],
    clock :: IORef UTCTime,
    -- | What the server asked GitHub: the URL, the Authorization header, the body.
    seen :: IORef [(Text, Text, ByteString)],
    respond :: IORef (GithubRequest -> IO (Int, ByteString)),
    extra :: [Route]
  }

data Req = Req
  { method :: Method,
    path :: ByteString,
    headers :: [Header],
    body :: BL.ByteString,
    peer :: String
  }

data Res = Res {status :: Int, headers :: [Header], body :: BL.ByteString} deriving (Show)

-- | A page of about 2 KB, so compression has something to do.
bulk :: Text
bulk = T.replicate 200 "marola 0123456789\n"

secret :: Text
secret = "TOP-SECRET-OUTSIDE-THE-ROOTS"

-- | A made-up OAuth client secret: a test fails if it shows up in a log or a response.
fakeClientSecret :: Text
fakeClientSecret = "fake-client-secret-0123456789"

write :: FilePath -> Text -> IO ()
write p t = createDirectoryIfMissing True (takeDirectory p) >> BS.writeFile p (TE.encodeUtf8 t)

tempDir :: String -> IO FilePath
tempDir prefix = do
  tmp <- getTemporaryDirectory
  token <- BC.unpack . StudyStore.hexLower <$> StudyStore.randomBytes 8
  let d = tmp </> (prefix <> token)
  createDirectoryIfMissing True d
  pure d

-- | @root/static@ (the page), @root/data@ (the boards), @root/secret.txt@ (outside both roots).
start :: (Config -> Config) -> [Route] -> IO Site
start tweak extra = do
  root <- tempDir "marola-tests-"
  let static = root </> "static"
      dataDir = root </> "data"
  write (root </> "secret.txt") secret
  write (root </> "github-secret") (fakeClientSecret <> "\n")
  write (static </> "index.html") ("<!doctype html><p>home</p>\n" <> bulk)
  write (static </> "contact.html") ("<!doctype html><form></form>\n" <> bulk)
  write (static </> "404.html") "<!doctype html><p>nada aqui</p>\n"
  write (static </> "en" </> "404.html") "<!doctype html><p>nothing here</p>\n"
  write (static </> "app.js") ("export const x = 1;\n" <> bulk)
  write (static </> "app.1a2b3c4d5e.js") "export const y = 2;\n"
  write (static </> "style.css") ("body { margin: 0 }\n" <> bulk)
  -- The pages the server renders read the catalogs under static/i18n, as in the built page.
  createDirectoryIfMissing True (static </> "i18n")
  mapM_ (\tag -> BS.readFile ("../../site/i18n" </> tag <> ".json") >>= BS.writeFile (static </> "i18n" </> tag <> ".json")) ["pt-BR", "en"]
  write (static </> "logo.svg") ("<svg></svg>" <> bulk)
  write (static </> "font.woff2") bulk
  write (static </> "photo.png") bulk
  write (static </> ".env") secret
  write (static </> "sub" </> "x.txt") "x"
  write (static </> "sub" </> ".hidden") secret
  write (static </> ".well-known" </> "security.txt") "Contact: https://example.org/report\n"
  write (static </> ".well-known" </> ".hidden") secret
  write (static </> "sub" </> ".well-known" </> "security.txt") secret
  write (static </> "data" </> "rio" </> "latest.json") "{\"from\":\"static\"}"
  write (static </> "data" </> "floripa" </> "latest.json") "{\"from\":\"static\"}"
  write (dataDir </> "floripa" </> "latest.json") "{\"from\":\"data\"}"
  let config =
        tweak
          Config
            { port = 0,
              static = static,
              dataDir = dataDir,
              db = root </> "db" </> "marola.db",
              studies = root </> "studies",
              studiesQuota = 1000000,
              dev = False,
              githubClientId = Just "test-client-id",
              githubSecretFile = Just (root </> "github-secret"),
              githubBase = "https://github.test",
              githubApiBase = "https://api.github.test"
            }
  logs <- newIORef []
  clock <- newIORef (UTCTime (fromGregorian 2026 11 11) (12 * 3600))
  seen <- newIORef []
  respond <- newIORef (\_ -> pure (404, ""))
  let logger category level message = atomicModifyIORef' logs (\ls -> (ls <> [category <> " " <> showLevel level <> " " <> message], ()))
      github r = do
        modifyIORef' seen (<> [(r.url, maybe "" TE.decodeUtf8 (lookup hAuthorization r.headers), r.body)])
        f <- readIORef respond
        f r
  env <- App.newEnv config (readIORef clock) github logger
  pure Site {env = env, root = root, config = config, logs = logs, clock = clock, seen = seen, respond = respond, extra = extra}
  where
    showLevel :: Level -> Text
    showLevel = T.pack . show

withSiteWith :: (Config -> Config) -> [Route] -> (Site -> IO a) -> IO a
withSiteWith tweak extra = bracket (start tweak extra) (\s -> removePathForcibly s.root)

withSite :: (Site -> IO a) -> IO a
withSite = withSiteWith id []

advance :: Site -> NominalDiffTime -> IO ()
advance site by = modifyIORef' site.clock (addUTCTime by)

logLines :: Site -> IO [Text]
logLines site = readIORef site.logs

get :: ByteString -> Req
get p = Req "GET" p [] "" "192.0.2.10"

post :: ByteString -> [Header] -> BL.ByteString -> Req
post p hs b = Req "POST" p hs b "192.0.2.10"

sockAddr :: String -> SockAddr
sockAddr s = case read s :: IP of
  IPv4 a -> SockAddrInet 0 (toHostAddress a)
  IPv6 a -> SockAddrInet6 0 0 (toHostAddress6 a) 0

-- | Sends a request through the whole pipeline, with @Host: localhost@ unless the test names one.
send :: Site -> Req -> IO Res
send site r = do
  chunks <- newIORef (BL.toChunks r.body)
  let hs = (if any ((== hHost) . fst) r.headers then [] else [(hHost, "localhost")]) <> r.headers <> [(hContentLength, BC.pack (show (BL.length r.body))) | r.method `elem` ["POST", "PUT"]]
      base = setPath defaultRequest r.path
      req =
        setRequestBodyChunks
          (atomicModifyIORef' chunks (\case [] -> ([], BS.empty); x : xs -> (xs, x)))
          base
            { requestMethod = r.method,
              -- setPath re-encodes the segments, which turns "/" into "".
              rawPathInfo = BC.takeWhile (/= '?') r.path,
              requestHeaders = hs,
              requestHeaderHost = lookup hHost hs,
              remoteHost = sockAddr r.peer,
              requestBodyLength = KnownLength (fromIntegral (BL.length r.body))
            }
  out <- newIORef Nothing
  _ <- App.applicationWith site.extra site.env req $ \res -> do
    let (st, rhs, withBody) = responseToStream res
    acc <- newIORef mempty
    withBody $ \stream -> stream (\b -> modifyIORef' acc (<> b)) (pure ())
    b <- toLazyByteString <$> readIORef acc
    writeIORef out (Just (Res (statusCode st) rhs b))
    pure ResponseReceived
  maybe (fail "no response") pure =<< readIORef out

header :: Res -> HeaderName -> Maybe ByteString
header res n = case [v | (k, v) <- res.headers, k == n] of
  [] -> Nothing
  vs -> Just (BS.intercalate "," vs)

bodyText :: Res -> Text
bodyText res = TE.decodeUtf8Lenient (BL.toStrict res.body)

-- | The @name=value@ pairs of the Set-Cookie headers.
cookies :: Res -> Map.Map ByteString ByteString
cookies res =
  Map.fromList
    [ (k, BS.drop 1 v)
    | (n, raw) <- res.headers,
      n == "Set-Cookie",
      let (k, v) = BC.break (== '=') (BC.takeWhile (/= ';') raw)
    ]

setCookieHeader :: Res -> ByteString -> Maybe ByteString
setCookieHeader res name = case [v | (n, v) <- res.headers, n == "Set-Cookie", (name <> "=") `BS.isPrefixOf` v] of
  v : _ -> Just v
  [] -> Nothing

formBody :: [(ByteString, ByteString)] -> BL.ByteString
formBody = BL.fromStrict . renderSimpleQuery False

goodForm :: [(ByteString, ByteString)]
goodForm = [("email", "ana@example.org"), ("message", TE.encodeUtf8 "A mensagem tem mais de dez caracteres."), ("website", "")]

-- | A POST of the contact form, as a browser on the site's own page sends it.
contactPost :: String -> Maybe ByteString -> [(ByteString, ByteString)] -> Req
contactPost peer origin pairs =
  (post "/contact" ([(hContentType, "application/x-www-form-urlencoded")] <> maybe [] (\o -> [("Origin", o)]) origin) (formBody pairs))
    { peer = if null peer then "192.0.2.10" else peer
    }

now0 :: UTCTime
now0 = UTCTime (fromGregorian 2026 11 11) (12 * 3600)

-- | A migrated database in a temp folder; the folder goes away after the test.
withDb :: (FilePath -> IO a) -> IO a
withDb body = bracket (tempDir "marola-store-") removePathForcibly $ \dir -> do
  let db = dir </> "marola.db"
  Store.init db
  StudyStore.migrate db
  body db

account :: Int64 -> Text -> Account
account i l = Account {githubId = i, login = l, createdGithubUtc = "2020-01-01T00:00:00Z"}

submission :: Submission
submission =
  Submission
    { title = "Water at Leblon",
      authors = [Author {name = "Ana Silva", orcid = Just "0000-0002-1825-0097"}, Author {name = "Bruno Costa", orcid = Nothing}],
      abstract = T.replicate 10 "Enterococcus counts at six points. ",
      area = Rio,
      topic = WaterQuality,
      sources = ["https://example.org/a", "https://example.org/b"],
      repository = Just "https://github.com/example/r",
      licence = CcBy40,
      aiModels = "",
      aiContribution = NoAi,
      aiProcess = ""
    }

hashOf :: Char -> Text
hashOf c = T.replicate 64 (T.singleton c)

bareConfig :: FilePath -> Config
bareConfig db =
  Config
    { port = 0,
      static = "",
      dataDir = "",
      db = db,
      studies = "",
      studiesQuota = 0,
      dev = False,
      githubClientId = Nothing,
      githubSecretFile = Nothing,
      githubBase = "",
      githubApiBase = ""
    }

-- | Runs a command-line entry point with its two outputs kept: (code, out, err).
lines' :: ((Text -> IO ()) -> (Text -> IO ()) -> IO Int) -> IO (Int, Text, Text)
lines' f = do
  out <- newIORef []
  err <- newIORef []
  code <- f (\l -> modifyIORef' out (<> [l])) (\l -> modifyIORef' err (<> [l]))
  (,,) code <$> (T.unlines <$> readIORef out) <*> (T.unlines <$> readIORef err)

latin1 :: Text -> ByteString
latin1 = BC.pack . T.unpack

-- | A tiny PDF: header, one object, trailer, @startxref@ and @%%EOF@. @extra@ goes into the catalog,
-- @padding@ bytes of comment make it as long as a test needs.
pdfBytes :: Text -> Int -> ByteString
pdfBytes extra padding =
  latin1 $
    "%PDF-1.4\n"
      <> (if padding > 0 then "%" <> T.replicate padding "x" <> "\n" else "")
      <> "1 0 obj\n<< /Type /Catalog /Pages 2 0 R "
      <> extra
      <> " >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\ntrailer\n<< /Root 1 0 R >>\nstartxref\n9\n%%EOF\n"

validPdf :: ByteString
validPdf = pdfBytes "" 0

sha :: ByteString -> Text
sha b = T.pack (show (hash b :: Digest SHA256))

-- | A part of a multipart body: its name, its bytes and, for a file, its file name.
data Part = Part {name :: ByteString, bytes :: BL.ByteString, file :: Maybe ByteString}

field :: ByteString -> Text -> Part
field n v = Part n (BL.fromStrict (TE.encodeUtf8 v)) Nothing

boundary :: ByteString
boundary = "marola-test-boundary-7f3a"

-- | The content type and the body, as HttpClient's MultipartFormDataContent writes them.
multipart :: [Part] -> ([Header], BL.ByteString)
multipart parts =
  ( [(hContentType, "multipart/form-data; boundary=\"" <> boundary <> "\"")],
    BL.concat (concatMap one parts) <> BL.fromStrict ("--" <> boundary <> "--\r\n")
  )
  where
    one p =
      [ BL.fromStrict ("--" <> boundary <> "\r\n"),
        BL.fromStrict $ case p.file of
          Nothing -> "Content-Type: text/plain; charset=utf-8\r\nContent-Disposition: form-data; name=" <> p.name <> "\r\n\r\n"
          Just f -> "Content-Disposition: form-data; name=" <> p.name <> "; filename=" <> f <> "; filename*=utf-8''" <> f <> "\r\n\r\n",
        p.bytes,
        "\r\n"
      ]

-- | The fields, then the file.
studyBody :: [(ByteString, Text)] -> Maybe ByteString -> ([Header], BL.ByteString)
studyBody fields pdf = multipart ([field k v | (k, v) <- fields] <> maybe [] (\b -> [Part "pdf" (BL.fromStrict b) (Just "study.pdf")]) pdf)

jsonOf :: Res -> A.Value
jsonOf res = maybe (error ("not JSON: " <> show res.body)) id (A.decode res.body)

jpath :: [Text] -> A.Value -> A.Value
jpath [] v = v
jpath (k : ks) (A.Object o) = jpath ks (maybe A.Null id (KM.lookup (K.fromText k) o))
jpath _ _ = A.Null

jtext :: [Text] -> A.Value -> Text
jtext ks v = case jpath ks v of
  A.String t -> t
  other -> T.pack (show other)

errorCodes :: Res -> [(Text, Text)]
errorCodes res = case jpath ["errors"] (jsonOf res) of
  A.Array es -> [(jtext ["field"] e, jtext ["code"] e) | e <- toList es]
  _ -> []

-- | Every file under a folder, at any depth; none when it is missing.
filesUnder :: FilePath -> IO [FilePath]
filesUnder dir = do
  exists <- doesDirectoryExist dir
  if not exists
    then pure []
    else do
      entries <- listDirectory dir
      concat <$> mapM (\e -> let p = dir </> e in doesDirectoryExist p >>= \d -> if d then filesUnder p else pure [p]) entries
