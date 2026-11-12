module LimitSpec (spec) where

import Control.Monad (forM, forM_, replicateM)
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.IP (IP)
import Data.Text qualified as T
import Harness
import Marola.Server.App qualified as App
import Marola.Server.Security qualified as Security
import Network.HTTP.Types (hContentType)
import Test.Hspec

statuses :: Site -> Int -> String -> (Int -> String) -> IO [Int]
statuses site count peer forwarded = forM [1 .. count] $ \i -> do
  let r = contactPost peer Nothing goodForm
      xff = forwarded i
  (.status) <$> send site r {headers = r.headers <> [("X-Forwarded-For", BC.pack xff) | xff /= ""]}

ip :: String -> IP
ip = read

spec :: Spec
spec = describe "limits and logging" $ do
  it "the 11th POST in the window gets 429 with Retry-After and the security headers" $ withSite $ \site -> do
    -- Without an Origin each POST is a 403: the limit counts requests, not outcomes.
    codes <- statuses site 11 "" (const "")
    take 10 codes `shouldBe` replicate 10 403
    last codes `shouldBe` 429
    refused <- send site (contactPost "" Nothing goodForm)
    refused.status `shouldBe` 429
    header refused "Retry-After" `shouldSatisfy` (/= Nothing)
    header refused "Content-Security-Policy" `shouldSatisfy` (/= Nothing)
    header refused "Strict-Transport-Security" `shouldSatisfy` (/= Nothing)

  it "X-Forwarded-For from the loopback splits clients" $ withSite $ \site -> do
    a <- statuses site 11 "127.0.0.1" (const "198.51.100.1")
    last a `shouldBe` 429
    b <- statuses site 1 "127.0.0.1" (const "198.51.100.2")
    b `shouldBe` [403]

  it "a spoofed X-Forwarded-For from another peer is ignored" $ withSite $ \site -> do
    codes <- statuses site 11 "203.0.113.9" (\i -> "198.51.100." <> show i)
    last codes `shouldBe` 429

  it "the general limit stops a flood of GETs" $ withSite $ \site -> do
    codes <- replicateM (App.generalPermits + 1) ((.status) <$> send site (get "/index.html"))
    last codes `shouldBe` 429
    take App.generalPermits codes `shouldBe` replicate App.generalPermits 200

  it "a body over 1 MB gets 413 before the handler, with the headers" $ withSite $ \site -> do
    res <- send site (post "/contact" [(hContentType, "application/x-www-form-urlencoded")] (BL.replicate (fromIntegral App.bodyLimit + 1) 97))
    res.status `shouldBe` 413
    header res "Content-Security-Policy" `shouldSatisfy` (/= Nothing)

  it "the log has the method, the path and the status, and no address, query or body" $ withSite $ \site -> do
    _ <- send site (get "/app.js?token=QUERY-SECRET") {headers = [("X-Forwarded-For", "203.0.113.77")], peer = "198.51.100.200"}
    _ <-
      send
        site
        (contactPost "198.51.100.201" (Just "http://localhost") [("email", "someone@example.org"), ("message", "BODY-SECRET text of the message"), ("website", "")])
    ls <- logLines site
    any (\l -> all (`T.isInfixOf` l) ["GET", "/app.js", "200"]) ls `shouldBe` True
    any ("stored" `T.isInfixOf`) ls `shouldBe` True
    forM_ ["QUERY-SECRET", "203.0.113.77", "198.51.100.200", "198.51.100.201", "BODY-SECRET", "someone@example.org", "127.0.0.1"] $ \s ->
      (s, any (s `T.isInfixOf`) ls) `shouldBe` (s, False)

  it "clientAddress: X-Forwarded-For counts only from the loopback, and its last entry" $ do
    Security.clientAddress (ip "127.0.0.1") "198.51.100.1" `shouldBe` ip "198.51.100.1"
    Security.clientAddress (ip "::1") "198.51.100.1" `shouldBe` ip "198.51.100.1"
    Security.clientAddress (ip "::ffff:127.0.0.1") "198.51.100.1" `shouldBe` ip "198.51.100.1"
    Security.clientAddress (ip "203.0.113.9") "198.51.100.1" `shouldBe` ip "203.0.113.9"
    Security.clientAddress (ip "127.0.0.1") "6.6.6.6, 198.51.100.1" `shouldBe` ip "198.51.100.1"
    Security.clientAddress (ip "127.0.0.1") "not an address" `shouldBe` ip "127.0.0.1"
    Security.clientAddress (ip "127.0.0.1") "" `shouldBe` ip "127.0.0.1"

  it "rateKey: an IPv6 client is its /64" $ do
    Security.rateKey (ip "2001:db8:1:2:aaaa::1") `shouldBe` Security.rateKey (ip "2001:db8:1:2:bbbb::2")
    Security.rateKey (ip "2001:db8:1:2::1") `shouldNotBe` Security.rateKey (ip "2001:db8:1:3::1")
    Security.rateKey (ip "198.51.100.1") `shouldBe` "198.51.100.1"
