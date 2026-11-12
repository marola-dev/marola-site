-- | Login with GitHub, the web flow with an empty scope: the only data read is the public profile
-- (id, login, creation date). The access token lives in one request and is dropped.
module Marola.Server.Github (loginPath, callbackPath, login, callback, newHttp) where

import Control.Exception (SomeException (..), try)
import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Int (Int64)
import Data.Scientific (floatingOrInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime, ZonedTime, zonedTimeToUTC)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Data.Typeable (typeOf)
import Marola.Server.Config (Config (..))
import Marola.Server.Http
import Marola.Server.Session qualified as Session
import Marola.Server.Store (utc)
import Marola.Server.StudyStore qualified as StudyStore
import Network.HTTP.Client qualified as H
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types
import Network.Wai
import System.Directory (doesFileExist)

loginPath, callbackPath :: Text
loginPath = "/auth/github/login"
callbackPath = "/auth/github/callback"

-- | The client of the two GitHub calls: 10 seconds, at most 64 KB of answer.
newHttp :: IO GithubHttp
newHttp = do
  manager <- newTlsManager
  pure $ \r -> do
    base <- H.parseRequest (T.unpack r.url)
    let req =
          base
            { H.method = r.method
            , H.requestHeaders = r.headers
            , H.requestBody = H.RequestBodyBS r.body
            , H.responseTimeout = H.responseTimeoutMicro 10000000
            }
    H.withResponse req manager $ \resp -> do
      body <- H.brReadSome (H.responseBody resp) 65536
      pure (statusCode (H.responseStatus resp), BL.toStrict body)

-- | The client id and the secret, or 'Nothing'. The secret is read from its file at each use and never held.
secret :: Config -> IO (Maybe (Text, Text))
secret cfg = case (cfg.githubClientId, cfg.githubSecretFile) of
  (Just cid, Just file) -> do
    exists <- doesFileExist file
    if not exists
      then pure Nothing
      else do
        s <- T.strip . TE.decodeUtf8 <$> readStrict file
        pure (if T.null s then Nothing else Just (cid, s))
  _ -> pure Nothing
  where
    readStrict f = BL.toStrict <$> BL.readFile f

-- | A plain answer with no text from GitHub and no detail of what failed.
page :: Int -> Text -> Response
page st t = responseLBS (toEnum st) [(hContentType, "text/plain; charset=utf-8"), (hCacheControl, "no-store")] (BL.fromStrict (TE.encodeUtf8 (t <> "\n")))

loginShape :: Text -> Bool
loginShape l = case T.uncons l of
  Just (c, rest) -> alnum c && T.length rest <= 38 && T.all (\x -> alnum x || x == '-') rest
  Nothing -> False
  where
    alnum x = isAsciiUpper x || isAsciiLower x || isDigit x

login :: Env -> Request -> IO Response
login env req = do
  let cfg = env.config
  s <- secret cfg
  case s of
    Nothing -> pure (page 503 "login is not configured")
    Just (clientId, _) -> do
      state <- TE.decodeUtf8 . hex <$> StudyStore.randomBytes 16
      let lang = if queryText req "lang" == "en" then "en" else "pt"
          -- GitHub uses the callback registered with the app. Dev mode names it, for a fake GitHub that has none.
          redirectUri =
            if cfg.dev
              then "&redirect_uri=" <> urlEncode True ("http://" <> maybe "" id (requestHeaderHost req) <> TE.encodeUtf8 callbackPath)
              else ""
          -- No `scope`: an empty scope reads public data only.
          location =
            TE.encodeUtf8 cfg.githubBase
              <> "/login/oauth/authorize?client_id="
              <> urlEncode True (TE.encodeUtf8 clientId)
              <> "&state="
              <> TE.encodeUtf8 state
              <> redirectUri
      pure $
        responseLBS
          status302
          [ (hLocation, location)
          , (hCacheControl, "no-store")
          , ("Set-Cookie", Session.setCookie cfg.dev (Session.stateCookie cfg.dev) (state <> "." <> lang) 600)
          ]
          ""
  where
    hex = StudyStore.hexLower

data Profile = Profile {pid :: Int64, plogin :: Text, created :: Text}

jsonObject :: (Int, ByteString) -> Maybe A.Object
jsonObject (st, body)
  | st < 200 || st > 299 = Nothing
  | otherwise = case A.decodeStrict body of
      Just (A.Object o) -> Just o
      _ -> Nothing

str :: A.Object -> A.Key -> Maybe Text
str o k = case KM.lookup k o of
  Just (A.String s) -> Just s
  _ -> Nothing

parseTime' :: Text -> Maybe UTCTime
parseTime' s = case iso8601ParseM (T.unpack s) of
  Just u -> Just u
  Nothing -> zonedTimeToUTC <$> (iso8601ParseM (T.unpack s) :: Maybe ZonedTime)

-- | The code for the profile. The token is a local of this function and goes out of scope with it.
fetchProfile :: Env -> Text -> Text -> Text -> IO (Maybe Profile)
fetchProfile env clientId clientSecret code = do
  let cfg = env.config
      form = renderSimpleQuery False [("client_id", TE.encodeUtf8 clientId), ("client_secret", TE.encodeUtf8 clientSecret), ("code", TE.encodeUtf8 code)]
  tokenAnswer <-
    env.github
      GithubRequest
        { method = "POST"
        , url = cfg.githubBase <> "/login/oauth/access_token"
        , headers = [(hAccept, "application/json"), (hUserAgent, "marola-front"), (hContentType, "application/x-www-form-urlencoded")]
        , body = form
        }
  case jsonObject tokenAnswer >>= (`str` "access_token") of
    Nothing -> pure Nothing
    Just token -> do
      user <-
        env.github
          GithubRequest
            { method = "GET"
            , url = cfg.githubApiBase <> "/user"
            , headers = [(hAuthorization, "Bearer " <> TE.encodeUtf8 token), (hAccept, "application/vnd.github+json"), (hUserAgent, "marola-front")]
            , body = ""
            }
      pure $ do
        o <- jsonObject user
        i <- case KM.lookup "id" o of
          Just (A.Number n) | Right v <- (floatingOrInteger n :: Either Double Integer), v > 0, v <= fromIntegral (maxBound :: Int64) -> Just (fromIntegral v)
          _ -> Nothing
        l <- str o "login"
        if loginShape l then Just () else Nothing
        c <- str o "created_at" >>= parseTime'
        Just (Profile i l (utc c))

callback :: Env -> Request -> IO Response
callback env req = do
  let cfg = env.config
      dev = cfg.dev
      stateName = Session.stateCookie dev
      -- The state is single-use: a replayed callback finds no cookie.
      clear = ("Set-Cookie", Session.clearCookie dev stateName)
      (state, lang) = case cookie req stateName of
        Nothing -> ("", "pt")
        Just c -> case T.breakOnEnd "." c of
          ("", _) -> ("", "pt")
          (before, after) -> (T.dropEnd 1 before, if after == "en" then "en" else "pt" :: Text)
      code = queryText req "code"
      withClear r = mapResponseHeaders (clear :) r
  s <- secret cfg
  case s of
    Nothing -> pure (withClear (page 503 "login is not configured"))
    Just (clientId, clientSecret)
      | T.null state || not (Session.safeEquals state (queryText req "state")) || T.null code || T.length code > 200 ->
          pure (withClear (page 400 "login failed: start again from the site"))
      | otherwise -> do
          result <- try (fetchProfile env clientId clientSecret code)
          profile <- case result of
            Right p -> pure p
            Left (SomeException e) -> do
              -- The type only: a message could carry a URL, and nothing here may carry a token.
              env.logger "Marola.Login" Warning ("github login failed " <> T.pack (show (typeOf e)))
              pure Nothing
          case profile of
            Nothing -> pure (withClear (page 502 "login failed: GitHub did not confirm the login"))
            Just p -> do
              now <- env.clock
              StudyStore.upsertAccount cfg.db now (StudyStore.Account p.pid p.plogin p.created)
              token <- StudyStore.createSession cfg.db now p.pid
              env.logger "Marola.Login" Information ("login " <> tshow p.pid)
              pure $
                responseLBS
                  status303
                  [ clear
                  , ("Set-Cookie", Session.setCookie dev (Session.sessionCookie dev) token StudyStore.sessionLifetime)
                  , (hLocation, if lang == "en" then "/en/account" else "/account")
                  , (hCacheControl, "no-store")
                  ]
                  ""
