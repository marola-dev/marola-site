-- | The contact messages: one SQLite file, one table. Statements are constants with bound parameters.
module Marola.Server.Store
  ( Message (..)
  , connect
  , init
  , insert
  , list
  , delete
  , utc
  , withConn
  )
where

import Control.Exception (bracket)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, formatTime)
import Database.SQLite.Simple
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)
import Prelude hiding (init)

data Message = Message {id :: Int64, createdUtc :: Text, email :: Text, body :: Text} deriving (Eq, Show)

-- | @yyyy-MM-ddTHH:mm:ssZ@: the one time format of the database, so text order is time order.
utc :: UTCTime -> Text
utc = T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"

-- | A connection with foreign keys on and a busy timeout, as every caller wants.
connect :: FilePath -> IO Connection
connect path = do
  c <- open path
  execute_ c "pragma foreign_keys = on"
  execute_ c "pragma busy_timeout = 5000"
  pure c

-- | Creates the folder, the file and the table when they are missing.
init :: FilePath -> IO ()
init path = do
  createDirectoryIfMissing True (takeDirectory path)
  withConn path $ \c ->
    execute_ c "create table if not exists messages (id integer primary key autoincrement, created_utc text not null, email text not null, body text not null)"

withConn :: FilePath -> (Connection -> IO a) -> IO a
withConn path = bracket (connect path) close

insert :: FilePath -> UTCTime -> Text -> Text -> IO Int64
insert path now email body = withConn path $ \c -> do
  execute c "insert into messages (created_utc, email, body) values (?, ?, ?)" (utc now, email, body)
  lastInsertRowId c

-- | Oldest first. A missing file is an empty inbox: reading must not create the database.
list :: FilePath -> IO [Message]
list path = do
  exists <- doesFileExist path
  if not exists
    then pure []
    else withConn path $ \c -> do
      rows <- query_ c "select id, created_utc, email, body from messages order by id"
      pure [Message i t e b | (i, t, e, b) <- rows]

-- | True when a row was deleted.
delete :: FilePath -> Int64 -> IO Bool
delete path i = do
  exists <- doesFileExist path
  if not exists
    then pure False
    else withConn path $ \c -> do
      execute c "delete from messages where id = ?" (Only i)
      (> 0) <$> changes c
