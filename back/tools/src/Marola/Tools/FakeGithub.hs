-- | A stand-in for GitHub's OAuth web flow and /user, for the smoke run and for running the server by
-- hand (docs/3-development.md). Dev only: the server takes its URL from MAROLA_GITHUB_BASE when
-- MAROLA_DEV=1. Every visitor is the same user; the profile is made up. Prints the port, then serves
-- until killed.
module Marola.Tools.FakeGithub (main, token) where

import Data.Aeson ((.=))
import Data.Aeson qualified as A
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Network.HTTP.Types
import Network.Socket
import Network.Wai
import Network.Wai.Handler.Warp qualified as Warp
import System.IO (hFlush, stdout)

token :: ByteString
token = "gho_fakeSmokeToken0123456789"

profile :: A.Value
profile = A.object ["id" .= (777 :: Int), "login" .= ("smoke-sci" :: Text), "created_at" .= ("2019-01-01T00:00:00Z" :: Text)]

app :: ByteString -> Application
app secret req respond = case (requestMethod req, pathInfo req) of
  ("GET", ["login", "oauth", "authorize"]) -> do
    -- The real GitHub sends the person back to the app's registered callback, with a code and the state.
    let q = queryString req
        param k = maybe "" id (join' (lookup k q))
        (base, query) = BC.break (== '?') (param "redirect_uri")
        kept = [(k, v) | (k, v) <- parseSimpleQuery (BC.drop 1 query), k /= "code", k /= "state"]
        back = base <> renderSimpleQuery True (kept <> [("code", "fakecode"), ("state", param "state")])
    respond (responseLBS status302 [("location", back)] "")
  ("POST", ["login", "oauth", "access_token"]) -> do
    body <- BL.toStrict <$> strictRequestBody req
    let f = parseSimpleQuery body
    if lookup "client_secret" f == Just secret && lookup "code" f == Just "fakecode"
      then respond (reply 200 (A.object ["access_token" .= BC.unpack token, "token_type" .= ("bearer" :: Text), "scope" .= ("" :: Text)]))
      else respond (reply 200 (A.object ["error" .= ("bad_verification_code" :: Text)]))
  ("GET", ["user"])
    | lookup hAuthorization (requestHeaders req) == Just ("Bearer " <> token) -> respond (reply 200 profile)
    | otherwise -> respond (reply 401 (A.object ["message" .= ("Bad credentials" :: Text)]))
  _ -> respond (reply 404 (A.object ["message" .= ("Not Found" :: Text)]))
  where
    reply code v = responseLBS (mkStatus code "") [(hContentType, "application/json")] (A.encode v)
    join' = maybe Nothing id

main :: [String] -> IO ()
main = \case
  (secret : rest) -> do
    let port = case rest of
          (p : _) -> read p
          [] -> 0
    sock <- socket AF_INET Stream defaultProtocol
    setSocketOption sock ReuseAddr 1
    bind sock (SockAddrInet port (tupleToHostAddress (127, 0, 0, 1)))
    listen sock 64
    bound <- socketPort sock
    print (fromIntegral bound :: Int)
    hFlush stdout
    Warp.runSettingsSocket Warp.defaultSettings sock (app (BC.pack secret))
  [] -> fail "usage: marola-tools fake-github <client-secret> [port]"
