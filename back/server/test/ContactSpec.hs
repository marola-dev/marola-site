module ContactSpec (spec) where

import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.Either (isLeft, isRight)
import Data.IORef
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime (..), fromGregorian)
import Harness
import Marola.Server.Config (Config (..))
import Marola.Server.Config qualified as Config
import Marola.Server.Contact qualified as Contact
import Marola.Server.Inbox qualified as Inbox
import Marola.Server.Store (Message (..))
import Marola.Server.Store qualified as Store
import Network.HTTP.Types (hContentType)
import System.Directory (doesFileExist, removePathForcibly)
import System.FilePath (isAbsolute, takeDirectory, (</>))
import Test.Hspec

same :: Maybe ByteString
same = Just "http://localhost"

stored :: Site -> IO [Message]
stored site = Store.list site.config.db

-- | A database path in an empty folder: nothing is created until a command writes.
withNoDb :: (FilePath -> IO a) -> IO a
withNoDb = bracket ((</> "marola.db") <$> tempDir "marola-db-") (removePathForcibly . takeDirectory)

run :: FilePath -> [Text] -> IO (Int, Text, Text)
run db args = do
  out <- newIORef []
  err <- newIORef []
  code <- Inbox.run (bareConfig db) args (\l -> modifyIORef' out (<> [l])) (\l -> modifyIORef' err (<> [l]))
  (,,) code <$> (T.unlines <$> readIORef out) <*> (T.unlines <$> readIORef err)

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2026 11 11) (12 * 3600)

utf8 :: Text -> ByteString
utf8 = TE.encodeUtf8

spec :: Spec
spec = describe "contact" $ do
  it "a good post is stored, trimmed, and answered with a redirect" $ withSite $ \site -> do
    res <- send site (contactPost "" same [("email", "  ana@example.org "), ("message", utf8 "  Olá, a água da Joaquina está boa?  "), ("website", ""), ("name", "Ana")])
    res.status `shouldBe` 303
    header res "Location" `shouldBe` Just "/contact-sent.html"
    header res "Content-Security-Policy" `shouldSatisfy` (/= Nothing)
    ms <- stored site
    map (\m -> (m.email, m.body, m.id)) ms `shouldBe` [("ana@example.org", "Olá, a água da Joaquina está boa?", 1)]
    map (\m -> T.takeEnd 1 m.createdUtc) ms `shouldBe` ["Z"]

  it "CSRF: the Origin, or failing it the Referer, must be this site" $ withSite $ \site -> do
    forM_ [("no Origin", Nothing), ("another site", Just "https://evil.example"), ("the null origin", Just "null"), ("same host, another port", Just "http://localhost:81"), ("garbage", Just "localhost")] $
      \(what, origin) -> do
        res <- send site (contactPost "" origin goodForm)
        (what :: String, res.status) `shouldBe` (what, 403)
    stored site >>= (`shouldBe` []) . map (.id)
    ok <- send site (contactPost "" (Just "http://LOCALHOST") goodForm)
    ok.status `shouldBe` 303
    let r = contactPost "" Nothing goodForm
    viaReferer <- send site r {headers = r.headers <> [("Referer", "http://localhost/contact")]}
    viaReferer.status `shouldBe` 303
    let w = contactPost "" (Just "https://evil.example") goodForm
    mismatch <- send site w {headers = w.headers <> [("Referer", "http://localhost/contact")]}
    mismatch.status `shouldBe` 403
    length <$> stored site >>= (`shouldBe` 2)

  it "the honeypot: a bot gets 200 and nothing is stored" $ withSite $ \site -> do
    res <- send site (contactPost "" same [("email", "bot@example.org"), ("message", "buy my pills, please"), ("website", "http://spam.example")])
    res.status `shouldBe` 200
    length <$> stored site >>= (`shouldBe` 0)

  it "a bad email or message is a 400 and nothing is stored" $ withSite $ \site -> do
    forM_
      [ ("no email", [("message", "mensagem longa o bastante")])
      , ("bad email", [("email", "not-an-email"), ("message", "mensagem longa o bastante")])
      , ("no message", [("email", "ana@example.org")])
      , ("short message", [("email", "ana@example.org"), ("message", "curta")])
      , ("a long message", [("email", "ana@example.org"), ("message", utf8 (T.replicate 4001 "a"))])
      , ("a NUL in the message", [("email", "ana@example.org"), ("message", "mensagem\NULlonga o bastante")])
      ]
      $ \(what, pairs) -> do
        res <- send site (contactPost "" same pairs)
        (what :: String, res.status) `shouldBe` (what, 400)
    length <$> stored site >>= (`shouldBe` 0)

  it "only a url-encoded form is accepted" $ withSite $ \site -> do
    json <- send site (post "/contact" [(hContentType, "application/json; charset=utf-8"), ("Origin", "http://localhost")] "{\"email\":\"a@b.co\"}")
    json.status `shouldBe` 415
    multi <- send site (post "/contact" [(hContentType, "multipart/form-data; boundary=x"), ("Origin", "http://localhost")] "--x\r\nContent-Disposition: form-data; name=\"email\"\r\n\r\nana@example.org\r\n--x--\r\n")
    multi.status `shouldBe` 415

  it "a message with SQL in it is stored as text" $ withSite $ \site -> do
    let txt = "x'); drop table messages; --"
    _ <- send site (contactPost "" same [("email", "ana@example.org"), ("message", txt)])
    _ <- send site (contactPost "" same goodForm)
    map (.body) <$> stored site >>= (`shouldBe` [TE.decodeUtf8 txt, "A mensagem tem mais de dez caracteres."])

  it "the English form posts to /en/contact and lands on the English thanks page" $ withSite $ \site -> do
    let r = contactPost "" same goodForm
    res <- send site r {path = "/en/contact"}
    res.status `shouldBe` 303
    header res "Location" `shouldBe` Just "/en/contact-sent.html"
    length <$> stored site >>= (`shouldBe` 1)

  it "GET /contact is the page, other methods are 405" $ withSite $ \site -> do
    page <- send site (get "/contact?sent=1")
    page.status `shouldBe` 200
    put <- send site (contactPost "" same goodForm) {method = "PUT"}
    put.status `shouldBe` 405

  it "email syntax" $ do
    forM_ ["a@b.co", "ana.silva+marola@example.com.br", "x@a-b.example", "  a@b.co  "] $ \good ->
      (good, isRight (Contact.validateEmail good)) `shouldBe` (good, True)
    forM_
      [ ""
      , "a"
      , "a@b"
      , "@b.co"
      , "a@@b.co"
      , "a b@c.de"
      , "a@b..de"
      , "a@-b.com"
      , "a@b-.com"
      , "<x>@y.zz"
      , "a,b@c.de"
      , "a\n@b.co"
      , "a@b.co, c@d.co"
      , "\"a\"@b.co"
      , T.replicate 65 "a" <> "@b.co"
      , "a@" <> T.replicate 250 "b" <> ".co"
      ]
      $ \bad -> (bad, isLeft (Contact.validateEmail bad)) `shouldBe` (bad, True)

  it "message length: 10 to 4000 characters after trimming" $ do
    isLeft (Contact.validateMessage (T.replicate 9 "a")) `shouldBe` True
    isRight (Contact.validateMessage (T.replicate 10 "a")) `shouldBe` True
    isRight (Contact.validateMessage (T.replicate 4000 "a")) `shouldBe` True
    isLeft (Contact.validateMessage (T.replicate 4001 "a")) `shouldBe` True
    isLeft (Contact.validateMessage ("   " <> T.replicate 9 "a" <> "   ")) `shouldBe` True
    isRight (Contact.validateMessage "linha um\r\n\tlinha dois") `shouldBe` True
    isLeft (Contact.validateMessage "linha um\ESC[31m vermelho") `shouldBe` True

  it "sameSite" $ do
    Contact.sameSite "marola.piabrota.art" "https://marola.piabrota.art" "" `shouldBe` True
    Contact.sameSite "127.0.0.1:8080" "http://127.0.0.1:8080" "" `shouldBe` True
    Contact.sameSite "marola.piabrota.art" "" "https://marola.piabrota.art/contact" `shouldBe` True
    Contact.sameSite "marola.piabrota.art" "https://marola.piabrota.art.evil.example" "" `shouldBe` False
    Contact.sameSite "marola.piabrota.art" "" "" `shouldBe` False
    Contact.sameSite "" "https://marola.piabrota.art" "" `shouldBe` False
    Contact.sameSite "marola.piabrota.art" "javascript:alert(1)" "" `shouldBe` False

  it "the store keeps ids, lists oldest first, deletes one, and init can run twice" $ withNoDb $ \db -> do
    Store.init db
    Store.init db
    a <- Store.insert db t0 "a@b.co" "first message"
    b <- Store.insert db t0 "c@d.co" "second message"
    (a, b) `shouldBe` (1, 2)
    map (.id) <$> Store.list db >>= (`shouldBe` [1, 2])
    map (.createdUtc) <$> Store.list db >>= (`shouldBe` ["2026-11-11T12:00:00Z", "2026-11-11T12:00:00Z"])
    Store.delete db 1 >>= (`shouldBe` True)
    Store.delete db 1 >>= (`shouldBe` False)
    map (.id) <$> Store.list db >>= (`shouldBe` [2])
    Store.insert db t0 "e@f.co" "third message" >>= (`shouldBe` 3)

  it "inbox prints the messages, deletes one, and refuses a bad call" $ withNoDb $ \db -> do
    Store.init db
    _ <- Store.insert db t0 "a@b.co" "first message\nsecond line"
    _ <- Store.insert db t0 "c@d.co" "another message"
    (code, out, _) <- run db []
    code `shouldBe` 0
    out `shouldSatisfy` T.isInfixOf "#1  2026-11-11T12:00:00Z  a@b.co"
    out `shouldSatisfy` T.isInfixOf "first message\nsecond line"
    out `shouldSatisfy` T.isInfixOf "#2  2026-11-11T12:00:00Z  c@d.co"
    (c1, o1, _) <- run db ["--delete", "1"]
    (c1, T.strip o1) `shouldBe` (0, "deleted #1")
    (_, o2, _) <- run db []
    o2 `shouldNotSatisfy` T.isInfixOf "a@b.co"
    (c3, _, e3) <- run db ["--delete", "99"]
    (c3, T.strip e3) `shouldBe` (1, "no message #99")
    forM_ [["--delete", "x"], ["--delete"], ["foo"]] $ \args -> do
      (c, _, _) <- run db args
      (args, c) `shouldBe` (args, 2)

  it "inbox on a missing database prints nothing and creates nothing" $ withNoDb $ \db -> do
    (code, out, _) <- run db []
    (code, out) `shouldBe` (0, "")
    doesFileExist db >>= (`shouldBe` False)
    (c, _, _) <- run db ["--delete", "1"]
    c `shouldBe` 1
    doesFileExist db >>= (`shouldBe` False)

  it "Config.fromEnv: defaults, overrides, a bad port" $ do
    let env pairs name = lookup name pairs
    Config.fromEnv (env []) >>= \case
      Right c -> do
        c.port `shouldBe` 8080
        c.static `shouldSatisfy` \s -> T.isSuffixOf "dist" (T.pack s) && isAbsolute s
        c.dataDir `shouldSatisfy` T.isSuffixOf "/data" . T.pack
        c.db `shouldSatisfy` T.isSuffixOf "data/marola.db" . T.pack
      Left e -> expectationFailure e
    Config.fromEnv (env [("MAROLA_PORT", "9001"), ("MAROLA_DB", "/var/lib/marola/m.db")]) >>= \case
      Right c -> (c.port, c.db) `shouldBe` (9001, "/var/lib/marola/m.db")
      Left e -> expectationFailure e
    forM_ ["0", "70000", "x", ""] $ \bad -> do
      r <- Config.fromEnv (env [("MAROLA_PORT", bad)])
      (bad, isLeft r) `shouldBe` (bad, True)
