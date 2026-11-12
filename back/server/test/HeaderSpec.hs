module HeaderSpec (spec) where

import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Harness
import Marola.Csp qualified as Csp
import Marola.Server.Http (Route (..))
import Network.HTTP.Types (HeaderName)
import Test.Hspec

expected :: [(HeaderName, ByteString)]
expected =
  [ ("Content-Security-Policy", TE.encodeUtf8 Csp.policy <> "; form-action 'self'")
  , ("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
  , ("X-Content-Type-Options", "nosniff")
  , ("Referrer-Policy", "strict-origin-when-cross-origin")
  , ("Permissions-Policy", "geolocation=(self), camera=(), microphone=(), payment=(), usb=()")
  , ("Cross-Origin-Opener-Policy", "same-origin")
  , ("Cross-Origin-Resource-Policy", "same-origin")
  ]

checkHeaders :: String -> Res -> Expectation
checkHeaders what res = do
  forM_ expected $ \(n, v) -> (what, n, header res n) `shouldBe` (what, n, Just v)
  (what, header res "Server", header res "X-Powered-By") `shouldBe` (what, Nothing, Nothing)

boom :: Route
boom = Route "GET" "/boom" False (\_ _ _ -> fail "DETAIL-THAT-MUST-NOT-LEAK")

encoded :: ByteString -> ByteString -> Req
encoded p enc = (get p) {headers = [("Accept-Encoding", enc) | enc /= ""]}

spec :: Spec
spec = describe "headers" $ do
  it "every header is on 200, 404, HEAD, 405, 500 and a rejected POST" $ withSiteWith id [boom] $ \site ->
    forM_ [("200", "GET", "/", 200), ("404", "GET", "/nope", 404), ("HEAD", "HEAD", "/", 200), ("405", "PUT", "/", 405), ("500", "GET", "/boom", 500), ("403", "POST", "/contact", 403)] $
      \(what, m, p, st) -> do
        res <- send site (get p) {method = m}
        (what, res.status) `shouldBe` (what, st)
        checkHeaders what res

  it "a 500 has no stack trace and no detail, and the log keeps the cause" $ withSiteWith id [boom] $ \site -> do
    res <- send site (get "/boom")
    bodyText res `shouldBe` "internal server error\n"
    ls <- logLines site
    any ("DETAIL-THAT-MUST-NOT-LEAK" `T.isInfixOf`) ls `shouldBe` True

  it "cache: no-cache for html and json, a day for fonts and images, immutable for hashed files" $ withSite $ \site ->
    forM_
      [ ("/", "no-cache")
      , ("/index.html", "no-cache")
      , ("/app.js", "no-cache")
      , ("/style.css", "no-cache")
      , ("/data/floripa/latest.json", "no-cache")
      , ("/font.woff2", "public, max-age=86400")
      , ("/photo.png", "public, max-age=86400")
      , ("/logo.svg", "public, max-age=86400")
      , ("/app.1a2b3c4d5e.js", "public, max-age=31536000, immutable")
      ]
      $ \(p, cache) -> do
        res <- send site (get p)
        (p, header res "Cache-Control") `shouldBe` (p, Just cache)

  it "a repeat request with the ETag gets 304 and the headers" $ withSite $ \site -> do
    first <- send site (get "/app.js")
    let Just etag = header first "ETag"
    second <- send site (get "/app.js") {headers = [("If-None-Match", etag)]}
    second.status `shouldBe` 304
    checkHeaders "304" second

  it "text types are compressed with br or gzip, binary types are not" $ withSite $ \site -> do
    forM_ ["/", "/app.js", "/style.css", "/logo.svg", "/data/floripa/latest.json"] $ \p -> do
      br <- send site (encoded p "br, gzip")
      (p, header br "Content-Encoding") `shouldBe` (p, Just "br")
      gz <- send site (encoded p "gzip")
      (p, header gz "Content-Encoding") `shouldBe` (p, Just "gzip")
    forM_ ["/font.woff2", "/photo.png"] $ \p -> do
      res <- send site (encoded p "br, gzip")
      (p, header res "Content-Encoding") `shouldBe` (p, Nothing)
    plain <- send site (encoded "/app.js" "")
    header plain "Content-Encoding" `shouldBe` Nothing
    compressed <- send site (encoded "/app.js" "br")
    checkHeaders "compressed" compressed
