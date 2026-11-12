module StudyStoreSpec (spec) where

import Control.Exception (SomeException, evaluate, try)
import Control.Monad (forM, forM_, replicateM)
import Data.ByteString qualified as BS
import Data.Either (isLeft, isRight)
import Data.List (nub, sort)
import Data.Maybe (fromJust, isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (addUTCTime)
import Harness
import Marola.Server.DevAccount qualified as DevAccount
import Marola.Server.Store qualified as Store
import Marola.Server.StudyStore (Account (..), KeyError (..), KeyInfo (..))
import Marola.Server.StudyStore qualified as StudyStore
import Marola.Study
import Test.Hspec

latin1File :: FilePath -> IO Text
latin1File p = T.pack . map (toEnum . fromIntegral) . BS.unpack <$> BS.readFile p

devAccount :: FilePath -> Maybe String -> [Text] -> IO (Int, Text, Text)
devAccount db dev args = do
  (c, o, e) <- lines' (DevAccount.run (bareConfig db) now0 dev args)
  pure (c, T.strip o, e)

spec :: Spec
spec = do
  describe "study store" $ do
    it "the migration creates the tables, sets user_version and runs twice without harm" $ withDb $ \db -> do
      StudyStore.version db >>= (`shouldBe` fromIntegral StudyStore.schemaVersion)
      tables <- StudyStore.tableNames db
      forM_ ["accounts", "api_keys", "studies", "reports", "messages"] $ \t -> tables `shouldContain` [t]
      StudyStore.upsertAccount db now0 (account 1 "ana")
      StudyStore.migrate db
      StudyStore.version db >>= (`shouldBe` fromIntegral StudyStore.schemaVersion)
      isJust <$> StudyStore.getAccount db 1 >>= (`shouldBe` True)

    it "a database of the contact form (with messages) migrates and keeps the messages" $ withDb $ \db -> do
      _ <- Store.insert db now0 "ana@example.org" "A message with some words."
      StudyStore.migrate db
      length <$> Store.list db >>= (`shouldBe` 1)

    it "an account updates its login and keeps its GitHub creation date" $ withDb $ \db -> do
      StudyStore.upsertAccount db now0 (account 7 "old")
      StudyStore.upsertAccount db now0 (account 7 "new") {createdGithubUtc = "2024-01-01T00:00:00Z"}
      Just a <- StudyStore.getAccount db 7
      (a.login, a.createdGithubUtc) `shouldBe` ("new", "2020-01-01T00:00:00Z")

    it "a key is msk_ and 52 base32 characters, verifies, and only its hash is stored" $ withDb $ \db -> do
      StudyStore.upsertAccount db now0 (account 1 "ana")
      Right key <- StudyStore.issueKey db now0 1
      T.isPrefixOf "msk_" key `shouldBe` True
      T.length key `shouldBe` 56
      StudyStore.keyShape key `shouldBe` True
      fmap (.login) <$> StudyStore.verifyKey db key >>= (`shouldBe` Just "ana")
      isNothing <$> StudyStore.verifyKey db (T.take 55 key <> (if T.isSuffixOf "a" key then "b" else "a")) >>= (`shouldBe` True)
      isNothing <$> StudyStore.verifyKey db "msk_" >>= (`shouldBe` True)
      file <- latin1File db
      key `T.isInfixOf` file `shouldBe` False
      StudyStore.hashKey key `T.isInfixOf` file `shouldBe` True

    it "at most three active keys per account; a revoked key frees a place and stops working" $ withDb $ \db -> do
      StudyStore.upsertAccount db now0 (account 1 "ana")
      StudyStore.upsertAccount db now0 (account 2 "bia")
      keys <- replicateM 3 (either (error . show) id <$> StudyStore.issueKey db now0 1)
      StudyStore.issueKey db now0 1 >>= (`shouldBe` Left TooManyKeys)
      isRight <$> StudyStore.issueKey db now0 2 >>= (`shouldBe` True)
      first : _ <- StudyStore.listKeys db 1
      StudyStore.revokeKey db now0 2 first.id >>= (`shouldBe` False)
      StudyStore.revokeKey db now0 1 first.id >>= (`shouldBe` True)
      StudyStore.revokeKey db now0 1 first.id >>= (`shouldBe` False)
      isNothing <$> StudyStore.verifyKey db (head keys) >>= (`shouldBe` True)
      isJust <$> StudyStore.verifyKey db (keys !! 1) >>= (`shouldBe` True)
      isRight <$> StudyStore.issueKey db now0 1 >>= (`shouldBe` True)

    it "a study round-trips, and the same file from the same account is refused once" $ withDb $ \db -> do
      let ana = account 1 "ana"
      StudyStore.upsertAccount db now0 ana
      StudyStore.upsertAccount db now0 (account 2 "bia")
      Just r <- StudyStore.insertStudy db now0 ana (hashOf 'a') submission
      validId r.id `shouldBe` True
      StudyStore.getStudy db r.id >>= (`shouldBe` Just r)
      isNothing <$> StudyStore.insertStudy db now0 ana (hashOf 'a') submission >>= (`shouldBe` True)
      StudyStore.findByHash db 1 (hashOf 'a') >>= (`shouldBe` Just r.id)
      isJust <$> StudyStore.insertStudy db now0 (account 2 "bia") (hashOf 'a') submission >>= (`shouldBe` True)
      isJust <$> StudyStore.insertStudy db now0 ana (hashOf 'b') submission >>= (`shouldBe` True)

    it "ids are not sequential" $ withDb $ \db -> do
      let ana = account 1 "ana"
      StudyStore.upsertAccount db now0 ana
      ids <- forM ['a' .. 't'] $ \c -> (.id) . fromJust <$> StudyStore.insertStudy db now0 ana (hashOf c) submission
      length (nub ids) `shouldBe` 20
      ids `shouldNotBe` sort ids

    it "the list is newest first, filters by area and topic and pages with before" $ withDb $ \db -> do
      let ana = account 1 "ana"
      StudyStore.upsertAccount db now0 ana
      let add i ar tp = (.id) . fromJust <$> StudyStore.insertStudy db (addUTCTime (fromIntegral i * 60) now0) ana (hashOf (toEnum (fromEnum 'a' + i))) submission {area = ar, topic = tp}
      a <- add (0 :: Int) Rio WaterQuality
      b <- add 1 Floripa Waves
      c <- add 2 Rio Waves
      let ids = fmap (map (.id))
      ids (StudyStore.listStudies db Nothing Nothing Nothing 50) >>= (`shouldBe` [c, b, a])
      ids (StudyStore.listStudies db (Just Rio) Nothing Nothing 50) >>= (`shouldBe` [c, a])
      ids (StudyStore.listStudies db (Just Rio) (Just Waves) Nothing 50) >>= (`shouldBe` [c])
      ids (StudyStore.listStudies db Nothing Nothing (Just c) 1) >>= (`shouldBe` [b])
      ids (StudyStore.listStudies db Nothing Nothing (Just "zzzzzzzzzz") 50) >>= (`shouldBe` [])

    it "hide keeps the row and marks it; counts since a time" $ withDb $ \db -> do
      let ana = account 1 "ana"
      StudyStore.upsertAccount db now0 ana
      Just r <- StudyStore.insertStudy db now0 ana (hashOf 'a') submission
      StudyStore.countSince db 1 (addUTCTime (-60) now0) >>= (`shouldBe` 1)
      StudyStore.countSince db 1 (addUTCTime 60 now0) >>= (`shouldBe` 0)
      StudyStore.hide db now0 r.id "wrong unit" >>= (`shouldBe` True)
      StudyStore.hide db now0 r.id "again" >>= (`shouldBe` False)
      Just h <- StudyStore.getStudy db r.id
      (h.status, h.hiddenReason) `shouldBe` (Hidden, Just "wrong unit")

    it "a study of an unknown account is refused by the foreign key" $ withDb $ \db -> do
      r <- try (StudyStore.insertStudy db now0 (account 99 "ghost") (hashOf 'a') submission >>= evaluate) :: IO (Either SomeException (Maybe Record))
      isLeft r `shouldBe` True

  describe "dev-account" $ do
    it "it refuses unless MAROLA_DEV=1 and creates nothing" $ withDb $ \db -> do
      (code, out, _) <- devAccount db Nothing ["--login", "ana", "--age-days", "30"]
      (code, out) `shouldBe` (1, "")
      (code0, _, _) <- devAccount db (Just "0") ["--login", "ana", "--age-days", "30"]
      code0 `shouldBe` 1

    it "it makes an account of the given age and a working key, and a third key is the last" $ withDb $ \db -> do
      (code, key, _) <- devAccount db (Just "1") ["--login", "ana", "--age-days", "30"]
      code `shouldBe` 0
      Just a <- StudyStore.verifyKey db key
      (a.login, a.createdGithubUtc) `shouldBe` ("ana", "2026-10-12T12:00:00Z")
      _ <- devAccount db (Just "1") ["--login", "ana", "--age-days", "30"]
      _ <- devAccount db (Just "1") ["--login", "ana", "--age-days", "30"]
      (c4, _, err) <- devAccount db (Just "1") ["--login", "ana", "--age-days", "30"]
      c4 `shouldBe` 1
      err `shouldSatisfy` T.isInfixOf "3 active keys"

    it "bad arguments print the usage" $ withDb $ \db -> do
      (c1, _, _) <- devAccount db (Just "1") ["--login", "ana"]
      c1 `shouldBe` 2
      (c2, _, _) <- devAccount db (Just "1") ["--login", "ana", "--age-days", "x"]
      c2 `shouldBe` 2
