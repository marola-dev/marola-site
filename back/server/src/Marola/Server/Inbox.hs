-- | @marola-server inbox [--delete <id>]@: how the board reads the messages, over ssh.
module Marola.Server.Inbox (usage, run) where

import Data.Text (Text)
import Data.Text qualified as T
import Marola.Server.Board (parseInt)
import Marola.Server.Config (Config (..))
import Marola.Server.Store (Message (..))
import Marola.Server.Store qualified as Store

usage :: Text
usage = "usage: marola-server inbox [--delete <id>]"

run :: Config -> [Text] -> (Text -> IO ()) -> (Text -> IO ()) -> IO Int
run config args out err = case args of
  [] -> do
    ms <- Store.list config.db
    mapM_ (\m -> out ("#" <> T.pack (show m.id) <> "  " <> m.createdUtc <> "  " <> m.email) >> out m.body >> out "") ms
    pure 0
  ["--delete", i] -> case parseInt 9223372036854775807 i of
    Just n -> do
      ok <- Store.delete config.db (fromInteger n)
      if ok
        then out ("deleted #" <> T.pack (show n)) >> pure 0
        else err ("no message #" <> T.pack (show n)) >> pure 1
    Nothing -> err usage >> pure 2
  _ -> err usage >> pure 2
