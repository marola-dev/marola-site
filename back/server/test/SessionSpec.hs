module SessionSpec (spec) where

import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as T
import Data.Time (UTCTime, addUTCTime)
import Database.SQLite.Simple (Only (..), close, open, query_)
import Harness
import Marola.Server.Session qualified as Session
import Marola.Server.StudyStore (Account (..))
import Marola.Server.StudyStore qualified as StudyStore
import System.Directory (removePathForcibly)
import System.FilePath ((</>))
import System.Posix.Files (fileMode, getFileStatus, intersectFileModes)
import Test.Hspec

withAccount :: (FilePath -> IO a) -> IO a
withAccount body = withDb $ \db -> StudyStore.upsertAccount db now0 (account 7 "ana") >> body db

at :: Double -> UTCTime
at h = addUTCTime (realToFrac (h * 3600)) now0

spec :: Spec
spec = describe "sessions" $ do
  it "a session is the account's for 12 hours, absolute, and then it is gone" $ withAccount $ \db -> do
    tok <- StudyStore.createSession db now0 7
    fmap ((.login) . fst) <$> StudyStore.getSession db (at 11.9) tok >>= (`shouldBe` Just "ana")
    isNothing <$> StudyStore.getSession db (at 12) tok >>= (`shouldBe` True)
    isNothing <$> StudyStore.getSession db (at 48) tok >>= (`shouldBe` True)

  it "using a session does not extend it" $ withAccount $ \db -> do
    tok <- StudyStore.createSession db now0 7
    isJust <$> StudyStore.getSession db (at 11) tok >>= (`shouldBe` True)
    isNothing <$> StudyStore.getSession db (at 12.5) tok >>= (`shouldBe` True)

  it "only the hash is stored, and a tampered or short value finds nothing" $ withAccount $ \db -> do
    tok <- StudyStore.createSession db now0 7
    T.length tok `shouldBe` 43
    [Only stored] <- bracket (open db) close (\c -> query_ c "select token_hash from sessions")
    stored `shouldNotBe` tok
    T.length stored `shouldBe` 64
    let flipped = (if T.head tok == 'A' then "B" else "A") <> T.drop 1 tok
    forM_ [flipped, T.drop 1 tok, tok <> "A", "", stored] $ \bad ->
      isNothing <$> StudyStore.getSession db now0 bad >>= (`shouldBe` True)

  it "logout deletes the row; another session of the account stays" $ withAccount $ \db -> do
    a <- StudyStore.createSession db now0 7
    b <- StudyStore.createSession db now0 7
    StudyStore.deleteSession db a >>= (`shouldBe` True)
    StudyStore.deleteSession db a >>= (`shouldBe` False)
    isNothing <$> StudyStore.getSession db now0 a >>= (`shouldBe` True)
    isJust <$> StudyStore.getSession db now0 b >>= (`shouldBe` True)

  it "safeEquals: equal, different at the end, different length" $ do
    Session.safeEquals "abc" "abc" `shouldBe` True
    Session.safeEquals "abc" "abd" `shouldBe` False
    Session.safeEquals "abc" "abcd" `shouldBe` False
    Session.safeEquals "" "abc" `shouldBe` False

  it "the CSRF token is bound to the session and to the key" $ bracket (tempDir "marola-key-") removePathForcibly $ \dir -> do
    let db = dir </> "m.db"
    key <- Session.loadKey db
    st <- getFileStatus (dir </> "csrf.key")
    (fileMode st `intersectFileModes` 0o777) `shouldBe` 0o600
    Session.loadKey db >>= (`shouldBe` key)
    let tok = Session.csrfToken key "session-a"
    Session.csrfValid key "session-a" tok `shouldBe` True
    Session.csrfValid key "session-b" tok `shouldBe` False
    Session.csrfValid key "session-a" "" `shouldBe` False
    Session.csrfValid key "session-a" (T.drop 1 tok <> "0") `shouldBe` False
    Session.csrfValid (BS.reverse key) "session-a" tok `shouldBe` False
