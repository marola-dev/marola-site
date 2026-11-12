module FileSpec (spec) where

import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Harness
import Marola.Server.App qualified as App
import Marola.Server.Files qualified as Files
import Network.HTTP.Client qualified as C
import Network.HTTP.Types (statusCode)
import Network.Wai.Handler.Warp (testWithApplication)
import System.Directory (setModificationTime)
import System.FilePath ((</>))
import Test.Hspec

-- | Paths as a client may send them, encoded or not. Each one must be a 404.
hostile :: [ByteString]
hostile =
  [ "/../secret.txt",
    "/%2e%2e/secret.txt",
    "/..%2fsecret.txt",
    "/%2e%2e%2fsecret.txt",
    "/..%5csecret.txt",
    "/..\\secret.txt",
    "/sub/../index.html",
    "/data/../secret.txt",
    "/data/..%2f..%2fsecret.txt",
    "/%252e%252e/secret.txt",
    "//index.html",
    "/sub//x.txt",
    "///",
    "/index.html\NUL",
    "/index.html%00",
    "/index.html\NUL.png",
    "/.env",
    "/sub/.hidden",
    "/.git/config",
    "/sub/",
    "/sub",
    "/index.html/",
    "/app.js/",
    "/ ",
    "/%20",
    "/index.html ",
    "/C:/windows/win.ini",
    "/sub/x.txt:stream",
    "/~/x",
    ""
  ]

shown :: ByteString -> String
shown = BC.unpack . BC.map (\c -> if c == '\NUL' then '0' else c)

spec :: Spec
spec = describe "static files" $ do
  it "a hostile path is a 404 and never the secret" $ withSite $ \site ->
    forM_ hostile $ \p -> do
      res <- send site (get p)
      (shown p, res.status) `shouldBe` (shown p, 404)
      (shown p, secret `T.isInfixOf` bodyText res) `shouldBe` (shown p, False)

  it "the same paths over HTTP, as a client would write them" $ withSite $ \site -> do
    manager <- C.newManager C.defaultManagerSettings
    testWithApplication (pure (App.applicationWith site.extra site.env)) $ \port ->
      forM_ ["/..%2fsecret.txt", "/%2e%2e/secret.txt", "/.env", "/sub/.hidden", "/sub//x.txt"] $ \p -> do
        base <- C.parseRequest ("http://127.0.0.1:" <> show port)
        res <- C.httpLbs base {C.path = p} manager
        (shown p, statusCode (C.responseStatus res)) `shouldBe` (shown p, 404)
        (shown p, secret `T.isInfixOf` TE.decodeUtf8Lenient (BL.toStrict (C.responseBody res))) `shouldBe` (shown p, False)

  it "the page: / and /index.html, files, and a clean URL for an html file" $ withSite $ \site ->
    forM_
      [ ("/", "text/html; charset=utf-8", "home"),
        ("/index.html", "text/html; charset=utf-8", "home"),
        ("/app.js", "text/javascript; charset=utf-8", "export const x"),
        ("/style.css", "text/css; charset=utf-8", "margin"),
        ("/sub/x.txt", "text/plain; charset=utf-8", "x"),
        ("/contact", "text/html; charset=utf-8", "<form>")
      ]
      $ \(p, kind, txt) -> do
        res <- send site (get p)
        (p, res.status, header res "Content-Type") `shouldBe` (p, 200, Just kind)
        bodyText res `shouldSatisfy` T.isInfixOf txt

  it "/.well-known/security.txt is served as text, and no other dot path is" $ withSite $ \site -> do
    ok <- send site (get "/.well-known/security.txt")
    ok.status `shouldBe` 200
    header ok "Content-Type" `shouldBe` Just "text/plain; charset=utf-8"
    bodyText ok `shouldSatisfy` T.isInfixOf "Contact:"
    forM_
      [ "/.well-known/.hidden",
        "/.well-known/",
        "/.well-known",
        "/sub/.well-known/security.txt",
        "/.well-known/../secret.txt",
        "/.well-known/%2e%2e/secret.txt",
        "/.env",
        "/.git/config"
      ]
      $ \p -> do
        res <- send site (get p)
        (p, res.status) `shouldBe` (p, 404)
        bodyText res `shouldNotSatisfy` T.isInfixOf secret

  it "a missing path gets the 404 page of its language, with status 404" $ withSite $ \site ->
    forM_ [("/nope", "nada aqui"), ("/en/nope", "nothing here")] $ \(p, txt) -> do
      res <- send site (get p)
      (p, res.status, header res "Content-Type") `shouldBe` (p, 404, Just "text/html; charset=utf-8")
      bodyText res `shouldSatisfy` T.isInfixOf txt

  it "an old /docs path is forwarded to docs.marola.dev, path and query kept" $ withSite $ \site ->
    forM_
      [ ("/docs", "https://docs.marola.dev/"),
        ("/docs/", "https://docs.marola.dev/"),
        ("/docs/3-development?x=1", "https://docs.marola.dev/3-development?x=1")
      ]
      $ \(p, to) -> do
        res <- send site (get p)
        (p, res.status, header res "Location") `shouldBe` (p, 301, Just to)

  it "a /docs path with a traversal or odd characters is still a 404" $ withSite $ \site ->
    forM_ ["/docs/../secret", "/docs/%2e%2e/x", "/docsx", "/docs/a\\b"] $ \p -> do
      res <- send site (get p)
      (p, res.status) `shouldBe` (p, 404)

  -- Warp drops the body of a HEAD answer; the headers are the pipeline's.
  it "HEAD has the headers" $ withSite $ \site -> do
    res <- send site (get "/app.js") {method = "HEAD"}
    res.status `shouldBe` 200
    header res "Content-Type" `shouldBe` Just "text/javascript; charset=utf-8"

  it "/data/ reads the data folder first and the page's own data folder second" $ withSite $ \site -> do
    floripa <- send site (get "/data/floripa/latest.json")
    bodyText floripa `shouldSatisfy` T.isInfixOf "\"data\""
    rio <- send site (get "/data/rio/latest.json")
    bodyText rio `shouldSatisfy` T.isInfixOf "\"static\""

  it "the ETag follows the content: same size and a Nix mtime of 1 still change it, and no Last-Modified" $ withSite $ \site -> do
    let file = site.root </> "static" </> "same.txt"
        nix = posixSecondsToUTCTime 1
    write file "aaaa\n"
    setModificationTime file nix
    first <- send site (get "/same.txt")
    write file "bbbb\n"
    setModificationTime file nix
    second <- send site (get "/same.txt")
    header first "ETag" `shouldNotBe` header second "ETag"
    header second "Last-Modified" `shouldBe` Nothing
    stale <- send site (get "/same.txt") {headers = [("If-None-Match", fromMaybe "" (header first "ETag"))]}
    stale.status `shouldBe` 200
    byDate <- send site (get "/same.txt") {headers = [("If-Modified-Since", "Thu, 01 Jan 1970 00:00:01 GMT")]}
    byDate.status `shouldBe` 200

  it "/?lang=en is the English map file when the build wrote one, and / is not" $ withSite $ \site -> do
    before <- send site (get "/?lang=en")
    bodyText before `shouldSatisfy` T.isInfixOf "home"
    write (site.root </> "static" </> "index.en.html") "<!doctype html><html lang=\"en\"><p>english home</p>\n"
    en <- send site (get "/?lang=en")
    bodyText en `shouldSatisfy` T.isInfixOf "english home"
    enIndex <- send site (get "/index.html?lang=en")
    bodyText enIndex `shouldSatisfy` T.isInfixOf "english home"
    pt <- send site (get "/")
    bodyText pt `shouldNotSatisfy` T.isInfixOf "english"

  it "a method other than GET and HEAD gets 405 with Allow" $ withSite $ \site ->
    forM_ ["PUT", "DELETE", "PATCH", "POST"] $ \m -> do
      res <- send site (get "/app.js") {method = m}
      (m, res.status, header res "Allow") `shouldBe` (m, 405, Just "GET, HEAD")

  it "segments: what is accepted and what is not" $ do
    Files.segments "/" `shouldBe` Just ["index.html"]
    Files.segments "/a/b.js" `shouldBe` Just ["a", "b.js"]
    Files.segments "/a/" `shouldBe` Just ["a", "index.html"]
    forM_ ["/..", "/a/../b", "/a//b", "/.x", "/a b", "/a%2fb", "/a\\b", "a", "", "/\NUL"] $ \bad ->
      (bad, Files.segments bad) `shouldBe` (bad, Nothing)
    Files.segments ("/" <> T.replicate 600 "a") `shouldBe` Nothing
