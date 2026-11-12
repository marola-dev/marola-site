-- | Accounts, API keys, sessions, studies and reports in the SQLite file of the contact form. The
-- schema moves by @PRAGMA user_version@, one step per version, so an older server reads a newer
-- database's tables it knows and ignores the rest. No email address is stored anywhere here.
module Marola.Server.StudyStore
  ( Account (..)
  , KeyError (..)
  , KeyInfo (..)
  , ReportRow (..)
  , maxActiveKeys
  , schemaVersion
  , version
  , migrate
  , upsertAccount
  , getAccount
  , keyPrefix
  , keyShape
  , hashKey
  , issueKey
  , verifyKey
  , listKeys
  , revokeKey
  , sessionLifetime
  , sessionTokenShape
  , createSession
  , getSession
  , deleteSession
  , insertStudy
  , getStudy
  , listStudies
  , countSince
  , findByHash
  , hide
  , tableNames
  , listByAuthor
  , withdrawnReason
  , withdraw
  , listForBoard
  , purgedUtc
  , publicWithHash
  , markPurged
  , unhide
  , listReports
  , closeReport
  , accountDeletedReason
  , deleteAccount
  , insertReport
  , countReports
  , sha256Hex
  , base32
  , randomBytes
  , hexLower
  )
where

import Control.Monad (forM_, when)
import Crypto.Hash (Digest, SHA256 (..), hashWith)
import Crypto.Random (getRandomBytes)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteArray (constEq)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteArray.Encoding (Base (Base16, Base64URLUnpadded), convertToBase)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Int (Int64)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (NominalDiffTime, UTCTime, addUTCTime)
import Database.SQLite.Simple
import Marola.Server.Store (utc, withConn)
import Marola.Study

data Account = Account {githubId :: Int64, login :: Text, createdGithubUtc :: Text} deriving (Eq, Show)

data KeyError = TooManyKeys deriving (Eq, Show)

data KeyInfo = KeyInfo {id :: Int64, createdUtc :: Text, revokedUtc :: Maybe Text} deriving (Eq, Show)

maxActiveKeys :: Int64
maxActiveKeys = 3

-- ---- schema --------------------------------------------------------------------------------------

-- | Version 1 adds the four tables. A later change appends a step; it never edits one.
steps :: [(Int, [Query])]
steps =
  [ ( 1
    , [ "create table accounts (\n\
        \                 github_id integer primary key,\n\
        \                 github_login text not null,\n\
        \                 created_github_utc text not null,\n\
        \                 created_utc text not null)"
      , "create table api_keys (\n\
        \                 id integer primary key autoincrement,\n\
        \                 github_id integer not null references accounts(github_id),\n\
        \                 key_hash text not null unique,\n\
        \                 created_utc text not null,\n\
        \                 revoked_utc text)"
      , "create table studies (\n\
        \                 id text primary key,\n\
        \                 received_utc text not null,\n\
        \                 sha256 text not null,\n\
        \                 title text not null,\n\
        \                 authors text not null,\n\
        \                 abstract text not null,\n\
        \                 area text not null,\n\
        \                 topic text not null,\n\
        \                 sources text not null,\n\
        \                 repository text,\n\
        \                 licence text not null,\n\
        \                 ai_models text not null,\n\
        \                 ai_contribution text not null,\n\
        \                 ai_process text not null,\n\
        \                 author_login text not null,\n\
        \                 author_github_id integer not null references accounts(github_id),\n\
        \                 status text not null default 'public',\n\
        \                 hidden_reason text,\n\
        \                 hidden_utc text,\n\
        \                 unique (author_github_id, sha256))"
      , "create index studies_received on studies (received_utc desc, id desc)"
      , "create table reports (\n\
        \                 id integer primary key autoincrement,\n\
        \                 study_id text not null references studies(id),\n\
        \                 created_utc text not null,\n\
        \                 reason text not null,\n\
        \                 reporter_github_id integer)"
      ]
    )
  , -- Only the SHA-256 of the cookie value is stored: a copy of the database cannot log anyone in.
    ( 2
    , [ "create table sessions (\n\
        \                 token_hash text primary key,\n\
        \                 github_id integer not null references accounts(github_id),\n\
        \                 created_utc text not null,\n\
        \                 expires_utc text not null)"
      ]
    )
  , -- Account deletion detaches a study from its author; the old table had a foreign key to
    -- `accounts`, which a detached study cannot satisfy, so the table is rebuilt without it.
    ( 3
    , [ "create table studies_new (\n\
        \                 id text primary key,\n\
        \                 received_utc text not null,\n\
        \                 sha256 text not null,\n\
        \                 title text not null,\n\
        \                 authors text not null,\n\
        \                 abstract text not null,\n\
        \                 area text not null,\n\
        \                 topic text not null,\n\
        \                 sources text not null,\n\
        \                 repository text,\n\
        \                 licence text not null,\n\
        \                 ai_models text not null,\n\
        \                 ai_contribution text not null,\n\
        \                 ai_process text not null,\n\
        \                 author_login text not null,\n\
        \                 author_github_id integer not null,\n\
        \                 status text not null default 'public',\n\
        \                 hidden_reason text,\n\
        \                 hidden_utc text,\n\
        \                 purged_utc text,\n\
        \                 unique (author_github_id, sha256))"
      , "insert into studies_new (id, received_utc, sha256, title, authors, abstract, area, topic, sources,\n\
        \                 repository, licence, ai_models, ai_contribution, ai_process, author_login, author_github_id,\n\
        \                 status, hidden_reason, hidden_utc)\n\
        \             select id, received_utc, sha256, title, authors, abstract, area, topic, sources,\n\
        \                 repository, licence, ai_models, ai_contribution, ai_process, author_login, author_github_id,\n\
        \                 status, hidden_reason, hidden_utc from studies"
      , "drop table studies"
      , "alter table studies_new rename to studies"
      , "create index studies_received on studies (received_utc desc, id desc)"
      , "create trigger studies_author_exists before insert on studies\n\
        \             when new.author_github_id > 0\n\
        \               and not exists (select 1 from accounts where github_id = new.author_github_id)\n\
        \             begin select raise(abort, 'FOREIGN KEY constraint failed: the author has no account'); end"
      , "alter table reports add column closed_utc text"
      , "alter table reports add column close_note text"
      ]
    )
  ]

schemaVersion :: Int
schemaVersion = maximum (map fst steps)

version :: FilePath -> IO Int64
version path = withConn path $ \c -> do
  [Only v] <- query_ c "pragma user_version"
  pure v

-- | Applies the steps above the file's @user_version@, each in a transaction. Safe at every start.
-- Foreign keys are off while the steps run: step 3 drops and renames a table @reports@ points at.
migrate :: FilePath -> IO ()
migrate path = withConn path $ \c -> do
  [Only current] <- query_ c "pragma user_version" :: IO [Only Int]
  execute_ c "pragma foreign_keys = off"
  forM_ steps $ \(v, statements) ->
    when (v > current) $
      withTransaction c $ do
        mapM_ (execute_ c) statements
        -- `pragma` takes no bound parameter; `v` is an int constant of this file.
        execute_ c (Query ("pragma user_version = " <> T.pack (show v)))

-- ---- accounts and keys ---------------------------------------------------------------------------

-- | The GitHub login calls this. A returning user updates the login, which GitHub lets people change.
upsertAccount :: FilePath -> UTCTime -> Account -> IO ()
upsertAccount path now a = withConn path $ \c ->
  execute
    c
    "insert into accounts (github_id, github_login, created_github_utc, created_utc) values (?, ?, ?, ?)\n\
    \ on conflict (github_id) do update set github_login = excluded.github_login"
    (a.githubId, a.login, a.createdGithubUtc, utc now)

getAccount :: FilePath -> Int64 -> IO (Maybe Account)
getAccount path gid = withConn path $ \c -> do
  rows <- query c "select github_id, github_login, created_github_utc from accounts where github_id = ?" (Only gid)
  pure (listToMaybe [Account i l t | (i, l, t) <- rows])

randomBytes :: Int -> IO ByteString
randomBytes = getRandomBytes

hexLower :: ByteString -> ByteString
hexLower = convertToBase Base16

sha256Hex :: ByteString -> Text
sha256Hex b = T.pack (show (hashWith SHA256 b :: Digest SHA256))

-- | RFC 4648 alphabet, lower case, no padding. 32 bytes give 52 characters.
base32 :: ByteString -> Text
base32 bytes = T.pack (go (BS.unpack bytes) (0 :: Int) (0 :: Int))
  where
    letter i = T.index idAlphabet i
    go [] buffer bits
      | bits > 0 = [letter ((buffer `shiftL` (5 - bits)) .&. 31)]
      | otherwise = []
    go (b : rest) buffer bits =
      let buffer' = (buffer `shiftL` 8) .|. fromIntegral b
          emit buf bs acc
            | bs >= 5 = emit buf (bs - 5) (letter ((buf `shiftR` (bs - 5)) .&. 31) : acc)
            | otherwise = (reverse acc, buf .&. ((1 `shiftL` bs) - 1), bs)
          (out, buf2, bits2) = emit buffer' (bits + 8) []
       in out <> go rest buf2 bits2

keyPrefix :: Text
keyPrefix = "msk_"

-- | @msk_@ and 52 base32 characters: the only text worth hashing and looking up.
keyShape :: Text -> Bool
keyShape k =
  T.length k == T.length keyPrefix + 52
    && keyPrefix `T.isPrefixOf` k
    && T.all (`T.elem` idAlphabet) (T.drop (T.length keyPrefix) k)

hashKey :: Text -> Text
hashKey = sha256Hex . TE.encodeUtf8

-- | A new key, shown once: only its SHA-256 is stored. At most three active keys per account.
issueKey :: FilePath -> UTCTime -> Int64 -> IO (Either KeyError Text)
issueKey path now gid = withConn path $ \c -> withTransaction c $ do
  [Only active] <- query c "select count(*) from api_keys where github_id = ? and revoked_utc is null" (Only gid)
  if (active :: Int64) >= maxActiveKeys
    then pure (Left TooManyKeys)
    else do
      key <- (keyPrefix <>) . base32 <$> randomBytes 32
      execute c "insert into api_keys (github_id, key_hash, created_utc) values (?, ?, ?)" (gid, hashKey key, utc now)
      pure (Right key)

sameHash :: Text -> Text -> Bool
sameHash a b = constEq (TE.encodeUtf8 a) (TE.encodeUtf8 b)

-- | The account an active key belongs to. The lookup is by hash; the comparison of the stored hash
-- with the computed one is constant time as well.
verifyKey :: FilePath -> Text -> IO (Maybe Account)
verifyKey path key
  | not (keyShape key) = pure Nothing
  | otherwise = withConn path $ \c -> do
      let h = hashKey key
      rows <-
        query
          c
          "select k.key_hash, a.github_id, a.github_login, a.created_github_utc\n\
          \ from api_keys k join accounts a on a.github_id = k.github_id\n\
          \ where k.key_hash = ? and k.revoked_utc is null"
          (Only h)
      pure $ case rows of
        (stored, i, l, t) : _ | sameHash stored h -> Just (Account i l t)
        _ -> Nothing

listKeys :: FilePath -> Int64 -> IO [KeyInfo]
listKeys path gid = withConn path $ \c -> do
  rows <- query c "select id, created_utc, revoked_utc from api_keys where github_id = ? order by id" (Only gid)
  pure [KeyInfo i t r | (i, t, r) <- rows]

-- | True when an active key of that account was revoked. A key of another account is never touched.
revokeKey :: FilePath -> UTCTime -> Int64 -> Int64 -> IO Bool
revokeKey path now gid keyId = withConn path $ \c -> do
  execute c "update api_keys set revoked_utc = ? where id = ? and github_id = ? and revoked_utc is null" (utc now, keyId, gid)
  (> 0) <$> changes c

-- ---- sessions ------------------------------------------------------------------------------------

-- | A session lasts 12 hours from login, absolute: using it does not extend it.
sessionLifetime :: NominalDiffTime
sessionLifetime = 12 * 3600

-- | A random 32-byte value, URL-safe, 43 characters. The hash of it is the session's id elsewhere.
sessionTokenShape :: Text -> Bool
sessionTokenShape tok = T.length tok == 43 && T.all ok tok
  where
    ok ch = isAsciiUpper ch || isAsciiLower ch || isDigit ch || ch == '-' || ch == '_'

-- | Returns the cookie value; the row holds its hash. Expired rows of any account go at the same time.
createSession :: FilePath -> UTCTime -> Int64 -> IO Text
createSession path now gid = withConn path $ \c -> do
  execute c "delete from sessions where expires_utc <= ?" (Only (utc now))
  token <- TE.decodeUtf8 . convertToBase Base64URLUnpadded <$> randomBytes 32
  execute
    c
    "insert into sessions (token_hash, github_id, created_utc, expires_utc) values (?, ?, ?, ?)"
    (hashKey token, gid, utc now, utc (addUTCTime sessionLifetime now))
  pure token

-- | The account of a live session and the hash that names it.
getSession :: FilePath -> UTCTime -> Text -> IO (Maybe (Account, Text))
getSession path now token
  | not (sessionTokenShape token) = pure Nothing
  | otherwise = withConn path $ \c -> do
      let h = hashKey token
      rows <-
        query
          c
          "select s.token_hash, a.github_id, a.github_login, a.created_github_utc\n\
          \ from sessions s join accounts a on a.github_id = s.github_id\n\
          \ where s.token_hash = ? and s.expires_utc > ?"
          (h, utc now)
      pure $ case rows of
        (stored, i, l, t) : _ | sameHash stored h -> Just (Account i l t, h)
        _ -> Nothing

-- | Logout. True when a row was deleted.
deleteSession :: FilePath -> Text -> IO Bool
deleteSession path token
  | not (sessionTokenShape token) = pure False
  | otherwise = withConn path $ \c -> do
      execute c "delete from sessions where token_hash = ?" (Only (hashKey token))
      (> 0) <$> changes c

-- ---- studies -------------------------------------------------------------------------------------

authorsText :: [Author] -> Text
authorsText as = T.intercalate "\n" [a.name <> "|" <> maybe "" Prelude.id a.orcid | a <- as]

parseAuthors :: Text -> [Author]
parseAuthors txt =
  [ let (nm, o) = T.breakOnEnd "|" l
     in Author (T.dropEnd 1 nm) (if T.null o then Nothing else Just o)
  | l <- T.splitOn "\n" txt
  ]

newId :: IO Text
newId = T.pack . map (\b -> T.index idAlphabet (fromIntegral b .&. 31)) . BS.unpack <$> randomBytes 10

-- | The study is public at once; @received_utc@ is the server's clock. 'Nothing' when this account
-- already sent this file (the unique index), which the caller reports as a 409.
insertStudy :: FilePath -> UTCTime -> Account -> Text -> Submission -> IO (Maybe Record)
insertStudy path now account sha s = withConn path $ \c -> do
  i <- newId
  executeNamed
    c
    "insert into studies (id, received_utc, sha256, title, authors, abstract, area, topic, sources,\n\
    \     repository, licence, ai_models, ai_contribution, ai_process, author_login, author_github_id)\n\
    \ values (:id, :now, :sha, :title, :authors, :abstract, :area, :topic, :sources,\n\
    \     :repo, :licence, :models, :level, :process, :login, :gid)\n\
    \ on conflict (author_github_id, sha256) do nothing"
    [ ":id" := i
    , ":now" := utc now
    , ":sha" := sha
    , ":title" := s.title
    , ":authors" := authorsText s.authors
    , ":abstract" := s.abstract
    , ":area" := areaName s.area
    , ":topic" := topicName s.topic
    , ":sources" := T.intercalate "\n" s.sources
    , ":repo" := s.repository
    , ":licence" := licenceName s.licence
    , ":models" := s.aiModels
    , ":level" := levelName s.aiContribution
    , ":process" := s.aiProcess
    , ":login" := account.login
    , ":gid" := account.githubId
    ]
  n <- changes c
  pure $
    if n == 0
      then Nothing
      else Just (Record i (utc now) sha s account.login account.githubId Public Nothing Nothing)

columns :: Text
columns =
  "id, received_utc, sha256, title, authors, abstract, area, topic, sources, repository, licence,\n\
  \ ai_models, ai_contribution, ai_process, author_login, author_github_id, status, hidden_reason, hidden_utc"

newtype Row = Row Record

instance FromRow Row where
  fromRow = do
    i <- field
    received <- field
    sha <- field
    title <- field
    authors <- field
    abstract <- field
    areaT <- field
    topicT <- field
    sources <- field
    repo <- field
    licenceT <- field
    models <- field
    levelT <- field
    process <- field
    login <- field
    gid <- field
    statusT <- field
    reason <- field
    hiddenAt <- field
    let must nm = maybe (error ("bad stored " <> nm)) Prelude.id
        sub =
          Submission
            { title = title
            , authors = parseAuthors authors
            , abstract = abstract
            , area = must "area" (parseArea areaT)
            , topic = must "topic" (parseTopic topicT)
            , sources = if T.null sources then [] else T.splitOn "\n" sources
            , repository = repo
            , licence = must "licence" (parseLicence licenceT)
            , aiModels = models
            , aiContribution = must "level" (parseLevel levelT)
            , aiProcess = process
            }
    pure (Row (Record i received sha sub login gid (must "status" (parseStatus statusT)) reason hiddenAt))

records :: [Row] -> [Record]
records = map (\(Row r) -> r)

select :: Text -> Query
select rest = Query ("select " <> columns <> " from studies " <> rest)

getStudy :: FilePath -> Text -> IO (Maybe Record)
getStudy path i = withConn path $ \c -> listToMaybe . records <$> query c (select "where id = ?") (Only i)

-- | Public studies only, newest first. @before@ is the id of the last study of the previous page.
-- Ids are random, so the order is by @received_utc@, then @id@, and @before@ is resolved to that pair.
listStudies :: FilePath -> Maybe Area -> Maybe Topic -> Maybe Text -> Int -> IO [Record]
listStudies path a tp before limit = withConn path $ \c ->
  records
    <$> queryNamed
      c
      ( select
          "where status = 'public' and (:area is null or area = :area) and (:topic is null or topic = :topic)\n\
          \ and (:before is null or (received_utc, id) < (select received_utc, id from studies where id = :before))\n\
          \ order by received_utc desc, id desc limit :limit"
      )
      [":area" := fmap areaName a, ":topic" := fmap topicName tp, ":before" := before, ":limit" := limit]

countSince :: FilePath -> Int64 -> UTCTime -> IO Int64
countSince path gid since = withConn path $ \c -> do
  [Only n] <- query c "select count(*) from studies where author_github_id = ? and received_utc >= ?" (gid, utc since)
  pure n

findByHash :: FilePath -> Int64 -> Text -> IO (Maybe Text)
findByHash path gid sha = withConn path $ \c ->
  fmap fromOnly . listToMaybe <$> query c "select id from studies where author_github_id = ? and sha256 = ?" (gid, sha)

-- | The board's tombstone: the file stays on disk, the API stops serving it.
hide :: FilePath -> UTCTime -> Text -> Text -> IO Bool
hide path now i reason = withConn path $ \c -> do
  execute
    c
    "update studies set status = 'hidden', hidden_reason = ?, hidden_utc = ? where id = ? and status = 'public'"
    (reason, utc now, i)
  (> 0) <$> changes c

tableNames :: FilePath -> IO [Text]
tableNames path = withConn path $ \c ->
  map fromOnly <$> query_ c "select name from sqlite_master where type = 'table' and name not like 'sqlite_%' order by name"

-- | Every study of one account, hidden ones too, newest first: the account page lists them.
listByAuthor :: FilePath -> Int64 -> IO [Record]
listByAuthor path gid = withConn path $ \c ->
  records <$> query c (select "where author_github_id = ? order by received_utc desc, id desc") (Only gid)

withdrawnReason :: Text
withdrawnReason = "withdrawn by the author"

-- | The author hides their own public study; another account's study is never touched.
withdraw :: FilePath -> UTCTime -> Int64 -> Text -> IO Bool
withdraw path now gid i = withConn path $ \c -> do
  execute
    c
    "update studies set status = 'hidden', hidden_reason = ?, hidden_utc = ?\n\
    \ where id = ? and author_github_id = ? and status = 'public'"
    (withdrawnReason, utc now, i, gid)
  (> 0) <$> changes c

-- ---- the board -----------------------------------------------------------------------------------

listForBoard :: FilePath -> Maybe Text -> Int -> IO [Record]
listForBoard path st limit = withConn path $ \c ->
  records
    <$> queryNamed
      c
      (select "where (:status is null or status = :status) order by received_utc desc, id desc limit :limit")
      [":status" := st, ":limit" := limit]

purgedUtc :: FilePath -> Text -> IO (Maybe Text)
purgedUtc path i = withConn path $ \c -> do
  rows <- query c "select purged_utc from studies where id = ?" (Only i)
  pure (case rows of (Only (Just t) : _) -> Just t; _ -> Nothing)

publicWithHash :: FilePath -> Text -> IO [Text]
publicWithHash path sha = withConn path $ \c ->
  map fromOnly <$> query c "select id from studies where sha256 = ? and status = 'public' order by id" (Only sha)

-- | Marks every study of this hash as purged: they share one file on disk.
markPurged :: FilePath -> UTCTime -> Text -> IO ()
markPurged path now sha = withConn path $ \c ->
  execute c "update studies set purged_utc = ? where sha256 = ? and purged_utc is null" (utc now, sha)

-- | The board republishes a hidden study. Refused when its file was purged or when its author
-- deleted the account: that author asked for the study to go.
unhide :: FilePath -> Text -> IO Bool
unhide path i = withConn path $ \c -> do
  execute
    c
    "update studies set status = 'public', hidden_reason = null, hidden_utc = null\n\
    \ where id = ? and status = 'hidden' and purged_utc is null and author_github_id > 0"
    (Only i)
  (> 0) <$> changes c

data ReportRow = ReportRow
  { id :: Int64
  , studyId :: Text
  , createdUtc :: Text
  , reason :: Text
  , closedUtc :: Maybe Text
  , closeNote :: Maybe Text
  }
  deriving (Eq, Show)

-- | Reports, oldest first, so the board answers in order.
listReports :: FilePath -> Bool -> IO [ReportRow]
listReports path openOnly = withConn path $ \c -> do
  rows <-
    query_
      c
      ( Query
          ( "select id, study_id, created_utc, reason, closed_utc, close_note from reports "
              <> (if openOnly then "where closed_utc is null " else "")
              <> "order by id"
          )
      )
  pure [ReportRow a b d e f g | (a, b, d, e, f, g) <- rows]

closeReport :: FilePath -> UTCTime -> Int64 -> Text -> IO Bool
closeReport path now i note = withConn path $ \c -> do
  execute c "update reports set closed_utc = ?, close_note = ? where id = ? and closed_utc is null" (utc now, note, i)
  (> 0) <$> changes c

-- ---- account deletion ----------------------------------------------------------------------------

accountDeletedReason :: Text
accountDeletedReason = "account deleted by the author"

-- | Deletes the keys, the sessions and the account row. Every study of the account is hidden and
-- detached: its author id becomes @-rowid@, which no GitHub id can be, and its login @deleted@.
-- Reports keep their text and lose the reporter's id. One transaction. Returns the studies hidden now.
deleteAccount :: FilePath -> UTCTime -> Int64 -> IO Int
deleteAccount path now gid = withConn path $ \c -> withTransaction c $ do
  execute
    c
    "update studies set status = 'hidden', hidden_reason = ?, hidden_utc = ? where author_github_id = ? and status = 'public'"
    (accountDeletedReason, utc now, gid)
  hidden <- changes c
  execute c "update studies set author_github_id = -rowid, author_login = 'deleted' where author_github_id = ?" (Only gid)
  execute c "update reports set reporter_github_id = null where reporter_github_id = ?" (Only gid)
  execute c "delete from api_keys where github_id = ?" (Only gid)
  execute c "delete from sessions where github_id = ?" (Only gid)
  execute c "delete from accounts where github_id = ?" (Only gid)
  pure hidden

-- | A report of a study: the time and the reason, and nothing that names the reporter.
insertReport :: FilePath -> UTCTime -> Text -> Text -> IO Bool
insertReport path now sid reason = withConn path $ \c -> do
  execute c "insert into reports (study_id, created_utc, reason) select id, ?, ? from studies where id = ?" (utc now, reason, sid)
  (> 0) <$> changes c

countReports :: FilePath -> Text -> IO Int64
countReports path sid = withConn path $ \c -> do
  [Only n] <- query c "select count(*) from reports where study_id = ?" (Only sid)
  pure n
