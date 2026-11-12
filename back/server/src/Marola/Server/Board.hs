-- | The board's command line, run over ssh: @marola-server studies ...@ and @marola-server reports
-- ...@. A port of app/Server/Board.fs. Everything is plain lines. Text that a visitor wrote (a title,
-- a report) goes through 'clean' first, so a hostile text cannot move the cursor, change the title
-- of the terminal or forge a line of output. Exit code: 0 done, 1 nothing changed, 2 wrong usage.
module Marola.Server.Board (usage, clean, parseInt, run) where

import Control.Exception (SomeException, try)
import Control.Monad (forM_, when)
import Data.Char (GeneralCategory (..), generalCategory, isDigit)
import Data.Int (Int64)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Marola.Server.Config (Config (..))
import Marola.Server.PdfIntake qualified as PdfIntake
import Marola.Server.Store (utc)
import Marola.Server.StudyStore (ReportRow (..))
import Marola.Server.StudyStore qualified as StudyStore
import Marola.Study
import Marola.Utf16 qualified as U
import System.Directory (doesFileExist, removeFile)

usage :: Text
usage =
  T.intercalate
    "\n"
    [ "usage: marola-server studies list [--status public|hidden] [--limit n]"
    , "       marola-server studies hide <id> --reason \"<text>\" [--purge]"
    , "       marola-server studies unhide <id>"
    , "       marola-server reports [--open]"
    , "       marola-server reports close <report-id> --note \"<text>\""
    , "exit code: 0 done, 1 nothing changed, 2 wrong usage"
    ]

-- | Replaces every control, format (for example the right-to-left override), line and paragraph
-- separator, unassigned and private-use character with a space, so stored text is one safe line.
clean :: Text -> Text
clean = T.map $ \c -> case generalCategory c of
  Control -> ' '
  Format -> ' '
  LineSeparator -> ' '
  ParagraphSeparator -> ' '
  Surrogate -> ' '
  NotAssigned -> ' '
  PrivateUse -> ' '
  _ -> c

shorten :: Int -> Text -> Text
shorten n text =
  let t = clean text
   in if U.len t <= n then t else U.take (n - 1) t <> "…"

-- | .NET's TryParse of an integer: white space around, an optional sign, digits, within @bound@.
parseInt :: Integer -> Text -> Maybe Integer
parseInt bound t =
  let s = T.strip t
      (sign, digits) = case T.uncons s of
        Just ('+', r) -> (1, r)
        Just ('-', r) -> (-1, r)
        _ -> (1, s)
   in if not (T.null digits) && T.all isDigit digits
        then let v = sign * read (T.unpack digits) in if v <= bound && v >= negate bound - 1 then Just v else Nothing
        else Nothing

int32 :: Text -> Maybe Int
int32 t = fromInteger <$> parseInt 2147483647 t

int64 :: Text -> Maybe Int64
int64 t = fromInteger <$> parseInt 9223372036854775807 t

-- | @--name value@ pairs and bare words. An unknown option or a missing value is 'Nothing'.
parse :: [Text] -> [Text] -> [Text] -> Maybe ([Text], Map.Map Text Text, Set.Set Text)
parse known flags = go [] Map.empty Set.empty
  where
    go words opts set = \case
      [] -> Just (reverse words, opts, set)
      a : rest | a `elem` flags -> go words opts (Set.insert a set) rest
      a : v : rest | a `elem` known -> go words (Map.insert a v opts) set rest
      a : _ | "--" `T.isPrefixOf` a -> Nothing
      w : rest -> go (w : words) opts set rest

line :: Record -> Int64 -> Text
line r reports =
  let s = r.submission
      hidden = case (r.status, r.hiddenUtc, r.hiddenReason) of
        (Hidden, Just t, Just why) -> "  hidden " <> t <> ": " <> shorten 120 why
        (Hidden, _, _) -> "  hidden"
        _ -> ""
   in r.id
        <> "  "
        <> statusName r.status
        <> "  "
        <> r.receivedUtc
        <> "  "
        <> areaName s.area
        <> "/"
        <> topicName s.topic
        <> "  reports "
        <> T.pack (show reports)
        <> "  @"
        <> shorten 40 r.authorLogin
        <> "  "
        <> shorten 80 s.title
        <> hidden

type Out = Text -> IO ()

studies :: Config -> UTCTime -> [Text] -> Out -> Out -> IO Int
studies config now args out err =
  let bad = err usage >> pure 2
      db = config.db
   in case args of
        "list" : rest -> case parse ["--status", "--limit"] [] rest of
          Just ([], opts, _) -> do
            let status = Map.lookup "--status" opts
                limit = int32 <$> Map.lookup "--limit" opts
            case (status, limit) of
              (Just s, _) | s /= "public" && s /= "hidden" -> bad
              (_, Just Nothing) -> bad
              (_, Just (Just n)) | n < 1 || n > 1000 -> bad
              _ -> do
                StudyStore.migrate db
                let n = maybe 50 (maybe 50 id) limit
                rs <- StudyStore.listForBoard db status n
                forM_ rs $ \r -> StudyStore.countReports db r.id >>= out . line r
                pure 0
          _ -> bad
        "hide" : rest -> case parse ["--reason"] ["--purge"] rest of
          Just ([i], opts, flags) -> do
            let reason = T.strip . clean <$> Map.lookup "--reason" opts
            case reason of
              Just r | U.len r >= 5 && U.len r <= 300 -> do
                StudyStore.migrate db
                found <- StudyStore.getStudy db i
                case found of
                  Nothing -> err ("no study " <> shorten 20 i) >> pure 1
                  Just study -> do
                    let purge = Set.member "--purge" flags
                    others <- filter (/= i) <$> StudyStore.publicWithHash db study.sha256
                    if
                      | purge && not (null others) -> do
                          -- One file serves every study of the same bytes; deleting it would break the others.
                          err ("other public studies use the same file: " <> T.intercalate ", " others <> ". Hide them too, then purge. Nothing changed.")
                          pure 1
                      | study.status == Hidden && not purge -> err (i <> " is hidden already") >> pure 1
                      | otherwise -> do
                          when (study.status == Public) $ do
                            _ <- StudyStore.hide db now i r
                            out ("hidden " <> i)
                          when purge $ do
                            let path = PdfIntake.pathOf config study.sha256
                            existed <- doesFileExist path
                            _ <- try (removeFile path) :: IO (Either SomeException ())
                            StudyStore.markPurged db now study.sha256
                            let what = if existed then "file deleted" else "no file on disk"
                            -- The board writes this line in its record: a restore of a backup brings the file back.
                            out ("purged " <> study.sha256 <> " (" <> what <> ") at " <> utc now)
                          pure 0
              _ -> err "--reason is required: 5 to 300 characters" >> pure 2
          _ -> bad
        ["unhide", i] -> do
          StudyStore.migrate db
          found <- StudyStore.getStudy db i
          case found of
            Nothing -> err ("no study " <> shorten 20 i) >> pure 1
            Just s -> do
              purged <- StudyStore.purgedUtc db i
              case purged of
                Just _ -> err (i <> ": the file was purged, so it cannot be shown again") >> pure 1
                Nothing -> do
                  ok <- StudyStore.unhide db i
                  if
                    | ok -> out ("public " <> i) >> pure 0
                    | s.status == Public -> err (i <> " is public already") >> pure 1
                    | otherwise -> err (i <> ": the author deleted the account, so it cannot be shown again") >> pure 1
        _ -> bad

reports :: Config -> UTCTime -> [Text] -> Out -> Out -> IO Int
reports config now args out err =
  let bad = err usage >> pure 2
      db = config.db
   in case args of
        "close" : rest -> case parse ["--note"] [] rest of
          Just ([i], opts, _) -> do
            let note = T.strip . clean <$> Map.lookup "--note" opts
            case (int64 i, note) of
              (Just n, Just t) | U.len t >= 3 && U.len t <= 300 -> do
                StudyStore.migrate db
                ok <- StudyStore.closeReport db now n t
                if ok
                  then out ("closed #" <> T.pack (show n)) >> pure 0
                  else err ("no open report #" <> T.pack (show n)) >> pure 1
              (Just _, _) -> err "--note is required: 3 to 300 characters" >> pure 2
              _ -> bad
          _ -> bad
        _ -> case parse [] ["--open"] args of
          Just ([], _, flags) -> do
            StudyStore.migrate db
            rs <- StudyStore.listReports db (Set.member "--open" flags)
            forM_ rs $ \r -> do
              let state = case (r.closedUtc, r.closeNote) of
                    (Just t, Just note) -> "closed " <> t <> ": " <> shorten 120 note
                    (Just t, Nothing) -> "closed " <> t
                    (Nothing, _) -> "open"
              out ("#" <> T.pack (show r.id) <> "  " <> r.createdUtc <> "  study " <> shorten 20 r.studyId <> "  " <> state)
              out ("    " <> shorten 1000 r.reason)
            pure 0
          _ -> bad

-- | @args@ starts with @studies@ or @reports@.
run :: Config -> UTCTime -> [Text] -> Out -> Out -> IO Int
run config now args out err = do
  exists <- doesFileExist config.db
  case args of
    w : _ | w `elem` ["studies", "reports"] && not exists -> err "there is no database yet: nothing to read" >> pure 1
    "studies" : rest -> studies config now rest out err
    "reports" : rest -> reports config now rest out err
    _ -> err usage >> pure 2
