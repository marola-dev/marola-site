module BoardSpec (spec) where

import Control.Monad (forM_, void)
import Data.ByteString qualified as B
import Data.Char (GeneralCategory (Control), generalCategory)
import Data.Int (Int64)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Harness
import Marola.Server.Board qualified as Board
import Marola.Server.Config (Config (..))
import Marola.Server.PdfIntake qualified as PdfIntake
import Marola.Server.Store qualified as Store
import Marola.Server.StudyStore qualified as StudyStore
import Marola.Study
import PdfSpec (withConfig)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import Test.Hspec

withBoard :: (Config -> IO a) -> IO a
withBoard body = withConfig 10_000_000 $ \config -> do
  Store.init config.db
  StudyStore.migrate config.db
  createDirectoryIfMissing True config.studies
  body config

run :: Config -> [Text] -> IO (Int, Text, Text)
run config args = lines' (Board.run config now0 args)

code :: Config -> [Text] -> IO Int
code config args = (\(c, _, _) -> c) <$> run config args

addStudy :: Config -> Int64 -> Text -> Text -> Char -> IO Text
addStudy config i l t h = do
  StudyStore.upsertAccount config.db now0 (account i l)
  let s = hashOf h
  B.writeFile (PdfIntake.pathOf config s) validPdf
  Just r <- StudyStore.insertStudy config.db now0 (account i l) s submission {title = t}
  pure r.id

noControls :: Text -> Bool
noControls = T.all (\c -> c == '\n' || generalCategory c /= Control)

outLines :: Text -> [Text]
outLines = T.splitOn "\n" . T.stripEnd

statusOf :: Config -> Text -> IO Status
statusOf config i = maybe (error "no study") (.status) <$> StudyStore.getStudy config.db i

spec :: Spec
spec = describe "board" $ do
  it "clean replaces controls, escape sequences, line breaks and bidi marks, and keeps letters" $ do
    let cleaned = Board.clean "a\ESC[2J\ab\r\nc\x202E\&d\x2028\&e\x85\&f\0g Ação 😀"
    cleaned `shouldBe` "a [2J b  c d e f g Ação 😀"
    T.all (\c -> generalCategory c /= Control) cleaned `shouldBe` True

  it "studies list shows every status, filters, limits and prints one safe line for each" $ withBoard $ \config -> do
    a <- addStudy config 1 "ana" "First study here" 'a'
    b <- addStudy config 2 "bruno" "Evil \ESC]0;pwned\a title\r\n#99 forged" 'b'
    StudyStore.hide config.db now0 b "wrong unit" `shouldReturn` True
    (c, out, _) <- run config ["studies", "list"]
    c `shouldBe` 0
    noControls out `shouldBe` True
    length (outLines out) `shouldBe` 2
    out `shouldSatisfy` T.isInfixOf "hidden 2026-11-11T12:00:00Z: wrong unit"
    (_, hiddenOnly, _) <- run config ["studies", "list", "--status", "hidden"]
    (b `T.isInfixOf` hiddenOnly, a `T.isInfixOf` hiddenOnly) `shouldBe` (True, False)
    (_, one, _) <- run config ["studies", "list", "--limit", "1"]
    length (outLines one) `shouldBe` 1
    code config ["studies", "list", "--status", "gone"] `shouldReturn` 2
    code config ["studies", "list", "--limit", "0"] `shouldReturn` 2
    code config ["studies", "list", "--limit"] `shouldReturn` 2

  it "hide needs a reason of 5 to 300 characters, hides, keeps the file and says so twice only once" $ withBoard $ \config -> do
    i <- addStudy config 1 "ana" "First study here" 'a'
    forM_ [["studies", "hide", i], ["studies", "hide", i, "--reason", "abcd"], ["studies", "hide", i, "--reason", T.replicate 301 "x"], ["studies", "hide", i, "--reason", "     \a "]] $ \args ->
      (args,) <$> code config args `shouldReturn` (args, 2)
    statusOf config i `shouldReturn` Public
    (c, out, _) <- run config ["studies", "hide", i, "--reason", "wrong claim\ESC[31m about a beach"]
    c `shouldBe` 0
    out `shouldSatisfy` T.isInfixOf ("hidden " <> i)
    Just study <- StudyStore.getStudy config.db i
    study.status `shouldBe` Hidden
    study.hiddenReason `shouldBe` Just "wrong claim [31m about a beach"
    doesFileExist (PdfIntake.pathOf config study.sha256) `shouldReturn` True
    (again, _, err) <- run config ["studies", "hide", i, "--reason", "second time"]
    again `shouldBe` 1
    err `shouldSatisfy` T.isInfixOf "hidden already"
    code config ["studies", "hide", "nosuchid", "--reason", "valid reason"] `shouldReturn` 1

  it "hide --purge deletes the file, keeps the row, the hash and the reason, and unhide is then refused" $ withBoard $ \config -> do
    i <- addStudy config 1 "ana" "First study here" 'a'
    let path = PdfIntake.pathOf config (hashOf 'a')
    (c, out, _) <- run config ["studies", "hide", i, "--reason", "defamation", "--purge"]
    c `shouldBe` 0
    out `shouldSatisfy` T.isInfixOf ("purged " <> hashOf 'a' <> " (file deleted)")
    doesFileExist path `shouldReturn` False
    Just study <- StudyStore.getStudy config.db i
    study.sha256 `shouldBe` hashOf 'a'
    study.hiddenReason `shouldBe` Just "defamation"
    isJust <$> StudyStore.purgedUtc config.db i `shouldReturn` True
    (c2, _, err) <- run config ["studies", "unhide", i]
    c2 `shouldBe` 1
    err `shouldSatisfy` T.isInfixOf "purged"
    statusOf config i `shouldReturn` Hidden

  it "a purge is refused while another public study uses the same file, and changes nothing" $ withBoard $ \config -> do
    one <- addStudy config 1 "ana" "First study here" 'a'
    two <- addStudy config 2 "bruno" "Second study here" 'a'
    (c, _, err) <- run config ["studies", "hide", one, "--reason", "defamation", "--purge"]
    c `shouldBe` 1
    err `shouldSatisfy` T.isInfixOf two
    statusOf config one `shouldReturn` Public
    doesFileExist (PdfIntake.pathOf config (hashOf 'a')) `shouldReturn` True
    code config ["studies", "hide", two, "--reason", "same file"] `shouldReturn` 0
    code config ["studies", "hide", one, "--reason", "defamation", "--purge"] `shouldReturn` 0
    isJust <$> StudyStore.purgedUtc config.db two `shouldReturn` True

  it "unhide shows a hidden study again; a public one and a deleted account are refused" $ withBoard $ \config -> do
    i <- addStudy config 1 "ana" "First study here" 'a'
    code config ["studies", "unhide", i] `shouldReturn` 1
    void (run config ["studies", "hide", i, "--reason", "check pending"])
    (c, out, _) <- run config ["studies", "unhide", i]
    c `shouldBe` 0
    out `shouldSatisfy` T.isInfixOf ("public " <> i)
    Just study <- StudyStore.getStudy config.db i
    study.status `shouldBe` Public
    study.hiddenReason `shouldBe` Nothing
    void (StudyStore.deleteAccount config.db now0 1)
    (c2, _, err) <- run config ["studies", "unhide", i]
    c2 `shouldBe` 1
    err `shouldSatisfy` T.isInfixOf "deleted the account"

  it "reports lists them with safe text, --open hides closed ones, close needs a note and works once" $ withBoard $ \config -> do
    i <- addStudy config 1 "ana" "First study here" 'a'
    void (StudyStore.insertReport config.db now0 i "harmful\ESC[2J\r\n#77  forged  study x open")
    void (StudyStore.insertReport config.db now0 i "second one")
    (c, out, _) <- run config ["reports"]
    c `shouldBe` 0
    noControls out `shouldBe` True
    length (outLines out) `shouldBe` 4
    out `shouldNotSatisfy` T.isInfixOf "\n#77"
    code config ["reports", "close", "1"] `shouldReturn` 2
    code config ["reports", "close", "1", "--note", "x"] `shouldReturn` 2
    code config ["reports", "close", "abc", "--note", "fine note"] `shouldReturn` 2
    (c2, closed, _) <- run config ["reports", "close", "1", "--note", "hid the study\ESC[0m"]
    c2 `shouldBe` 0
    closed `shouldSatisfy` T.isInfixOf "closed #1"
    (_, open', _) <- run config ["reports", "--open"]
    length (outLines open') `shouldBe` 2
    open' `shouldNotSatisfy` T.isInfixOf "#1 "
    (_, everything, _) <- run config ["reports"]
    everything `shouldSatisfy` T.isInfixOf "closed 2026-11-11T12:00:00Z: hid the study [0m"
    code config ["reports", "close", "1", "--note", "again fine"] `shouldReturn` 1
    code config ["reports", "close", "99", "--note", "no such"] `shouldReturn` 1

  it "wrong usage is 2, and a missing database is 1 and is not created" $ do
    withConfig 1 $ \config -> do
      code config ["studies", "list"] `shouldReturn` 1
      doesFileExist config.db `shouldReturn` False
      code config ["nonsense"] `shouldReturn` 2
    withBoard $ \config -> do
      code config ["studies"] `shouldReturn` 2
      code config ["studies", "hide"] `shouldReturn` 2
      code config ["reports", "--bogus"] `shouldReturn` 2
