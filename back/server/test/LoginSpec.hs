module LoginSpec (spec) where

import Control.Exception (throwIO)
import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Harness
import Marola.Server.Config (Config (..))
import Marola.Server.Http (GithubRequest (..))
import Marola.Server.StudyStore (Account (..))
import Marola.Server.StudyStore qualified as StudyStore
import Network.HTTP.Types (parseSimpleQuery)
import Test.Hspec

token :: ByteString
token = "gho_FAKE_ACCESS_TOKEN_0123456789"

pathOf :: GithubRequest -> Text
pathOf r = T.takeWhile (/= '?') (T.dropWhile (/= '/') (T.drop 8 r.url))

-- | A GitHub that confirms the code and says who the user is.
friendly :: Site -> IO ()
friendly site = writeIORef site.respond $ \r -> pure $ case pathOf r of
  "/login/oauth/access_token" -> (200, "{\"access_token\":\"" <> token <> "\",\"token_type\":\"bearer\"}")
  "/user" -> (200, "{\"id\":4242,\"login\":\"ana-bia\",\"created_at\":\"2020-05-06T07:08:09Z\",\"email\":\"never@example.org\"}")
  _ -> (404, "")

withCookie :: ByteString -> Maybe ByteString -> Req
withCookie url c = (get url) {headers = maybe [] (\v -> [("Cookie", v)]) c}

locationQuery :: Res -> [(ByteString, ByteString)]
locationQuery res = maybe [] (parseSimpleQuery . BS.drop 1 . BC.dropWhile (/= '?')) (header res "Location")

-- | The state cookie the server set and the state in the URL it sent the browser to.
startLogin :: Site -> ByteString -> IO (ByteString, ByteString)
startLogin site url = do
  res <- send site (get url)
  pure (Map.findWithDefault "" "__Host-mstate" (cookies res), maybe "" id (lookup "state" (locationQuery res)))

callbackWith :: Site -> IO Res
callbackWith site = do
  (st, param) <- startLogin site "/auth/github/login"
  send site (withCookie ("/auth/github/callback?code=c&state=" <> param) (Just ("__Host-mstate=" <> st)))

spec :: Spec
spec = describe "github login" $ do
  it "login redirects to GitHub with a state, an empty scope and a Secure HttpOnly Lax cookie" $ withSite $ \site -> do
    res <- send site (get "/auth/github/login")
    res.status `shouldBe` 302
    fmap (BC.takeWhile (/= '?')) (header res "Location") `shouldBe` Just "https://github.test/login/oauth/authorize"
    let q = locationQuery res
    lookup "client_id" q `shouldBe` Just "test-client-id"
    lookup "scope" q `shouldBe` Nothing
    lookup "client_secret" q `shouldBe` Nothing
    let Just c = setCookieHeader res "__Host-mstate"
    forM_ ["httponly", "secure", "samesite=lax", "path=/", "max-age=600"] $ \part -> c `shouldSatisfy` BS.isInfixOf part
    c `shouldNotSatisfy` BS.isInfixOf "domain"
    let Just st = lookup "state" q
    Map.findWithDefault "" "__Host-mstate" (cookies res) `shouldSatisfy` BS.isInfixOf st

  it "a good callback makes the account at GitHub's date, starts a session and drops the token" $ withSite $ \site -> do
    friendly site
    (st, param) <- startLogin site "/auth/github/login"
    back <- send site (withCookie ("/auth/github/callback?code=abc123&state=" <> param) (Just ("__Host-mstate=" <> st)))
    back.status `shouldBe` 303
    header back "Location" `shouldBe` Just "/account"
    let Just sess = setCookieHeader back "__Host-msess"
    forM_ ["httponly", "secure", "samesite=lax"] $ \part -> sess `shouldSatisfy` BS.isInfixOf part
    fmap (\a -> (a.login, a.createdGithubUtc)) <$> StudyStore.getAccount site.config.db 4242 >>= (`shouldBe` Just ("ana-bia", "2020-05-06T07:08:09Z"))
    now <- readIORef site.clock
    live <- StudyStore.getSession site.config.db now (TE.decodeUtf8 (Map.findWithDefault "" "__Host-msess" (cookies back)))
    isJust live `shouldBe` True
    seenCalls <- readIORef site.seen
    length seenCalls `shouldBe` 2
    let [(_, _, tokenBody), (_, auth, _)] = seenCalls
    TE.decodeUtf8 tokenBody `shouldSatisfy` T.isInfixOf fakeClientSecret
    auth `shouldBe` "Bearer " <> TE.decodeUtf8 token
    everything <- T.unlines <$> logLines site
    forM_ [TE.decodeUtf8 token, fakeClientSecret, "abc123"] $ \s -> (s, s `T.isInfixOf` everything) `shouldBe` (s, False)
    sess `shouldNotSatisfy` BS.isInfixOf token
    setCookieHeader back "__Host-mstate" `shouldSatisfy` maybe False (BS.isInfixOf "expires=Thu, 01 Jan 1970")

  it "an English login returns to /en/account; a returning user keeps the id and takes the new login" $ withSite $ \site -> do
    friendly site
    (st, param) <- startLogin site "/auth/github/login?lang=en"
    back <- send site (withCookie ("/auth/github/callback?code=c&state=" <> param) (Just ("__Host-mstate=" <> st)))
    header back "Location" `shouldBe` Just "/en/account"
    writeIORef site.respond $ \r -> pure $ case pathOf r of
      "/login/oauth/access_token" -> (200, "{\"access_token\":\"" <> token <> "\"}")
      _ -> (200, "{\"id\":4242,\"login\":\"ana-renamed\",\"created_at\":\"2020-05-06T07:08:09Z\"}")
    again <- callbackWith site
    again.status `shouldBe` 303
    fmap (.login) <$> StudyStore.getAccount site.config.db 4242 >>= (`shouldBe` Just "ana-renamed")

  it "a wrong, missing or replayed state is refused and nothing is created" $ withSite $ \site -> do
    friendly site
    (st, param) <- startLogin site "/auth/github/login"
    let c = Just ("__Host-mstate=" <> st)
    wrong <- send site (withCookie "/auth/github/callback?code=c&state=0000" c)
    wrong.status `shouldBe` 400
    missing <- send site (withCookie ("/auth/github/callback?code=c&state=" <> param) Nothing)
    missing.status `shouldBe` 400
    empty <- send site (withCookie "/auth/github/callback?code=c&state=" (Just "__Host-mstate=.pt"))
    empty.status `shouldBe` 400
    nocode <- send site (withCookie ("/auth/github/callback?state=" <> param) c)
    nocode.status `shouldBe` 400
    readIORef site.seen >>= (`shouldBe` 0) . length
    isNothing <$> StudyStore.getAccount site.config.db 4242 >>= (`shouldBe` True)
    Map.member "__Host-msess" (cookies wrong) `shouldBe` False

  it "a GitHub error shows no detail from GitHub and creates nothing" $ withSite $ \site -> do
    writeIORef site.respond $ \_ -> pure (200, "{\"error\":\"bad_verification_code\",\"error_description\":\"The code passed is incorrect\"}")
    a <- callbackWith site
    a.status `shouldBe` 502
    bodyText a `shouldNotSatisfy` (\t -> "bad_verification_code" `T.isInfixOf` t || "incorrect" `T.isInfixOf` t)
    writeIORef site.respond $ \r -> pure (if pathOf r == "/user" then (500, "{}") else (200, "{\"access_token\":\"" <> token <> "\"}"))
    b <- callbackWith site
    b.status `shouldBe` 502
    writeIORef site.respond $ \r -> pure (if pathOf r == "/user" then (200, "{\"id\":\"x\",\"login\":\"a b\"}") else (200, "{\"access_token\":\"" <> token <> "\"}"))
    c <- callbackWith site
    c.status `shouldBe` 502
    writeIORef site.respond $ \_ -> throwIO (userError ("boom " <> BC.unpack token))
    d <- callbackWith site
    d.status `shouldBe` 502
    isNothing <$> StudyStore.getAccount site.config.db 4242 >>= (`shouldBe` True)
    everything <- T.unlines <$> logLines site
    everything `shouldNotSatisfy` T.isInfixOf (TE.decodeUtf8 token)

  it "without the client id or the secret file login answers 503 and the rest of the site works"
    $ forM_
      [ \c -> c {githubClientId = Nothing},
        \c -> c {githubSecretFile = Nothing},
        \c -> c {githubSecretFile = Just "/nonexistent/secret"}
      ]
    $ \tweak -> withSiteWith tweak [] $ \site -> do
      login <- send site (get "/auth/github/login")
      login.status `shouldBe` 503
      back <- send site (get "/auth/github/callback?code=c&state=s")
      back.status `shouldBe` 503
      home <- send site (get "/contact.html")
      home.status `shouldBe` 200
