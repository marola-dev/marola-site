-- | @marola-server dev-account --login <name> --age-days <n>@: an account and an API key for the
-- smoke test. Real accounts come from the GitHub login. It refuses unless MAROLA_DEV=1, so it
-- cannot mint a key by mistake.
module Marola.Server.DevAccount (usage, idOf, run) where

import Crypto.Hash (Digest, SHA256, hash)
import Data.Bits (shiftL, (.&.), (.|.))
import Data.ByteArray qualified as BA
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime, addUTCTime)
import Marola.Server.Board (parseInt)
import Marola.Server.Config (Config (..))
import Marola.Server.Store (utc)
import Marola.Server.Store qualified as Store
import Marola.Server.StudyStore (Account (..), KeyError (..))
import Marola.Server.StudyStore qualified as StudyStore

usage :: Text
usage = "usage: marola-server dev-account --login <name> --age-days <n>   (needs MAROLA_DEV=1)"

-- | The same login gives the same id, so a second run reuses the account: the first 8 bytes of its
-- SHA-256, little-endian as BitConverter reads them, below 2^62.
idOf :: Text -> Int64
idOf login =
  let d = BA.unpack (hash (TE.encodeUtf8 login) :: Digest SHA256)
      w = foldr (\b acc -> (acc `shiftL` 8) .|. fromIntegral b) (0 :: Int64) (take 8 d)
   in w .&. 0x3fffffffffffffff

run :: Config -> UTCTime -> Maybe String -> [Text] -> (Text -> IO ()) -> (Text -> IO ()) -> IO Int
run config now dev args out err
  | dev /= Just "1" = err "dev-account is for tests: set MAROLA_DEV=1" >> pure 1
  | ["--login", login, "--age-days", days] <- args
  , not (T.null login) =
      case parseInt 2147483647 days of
        Just n | n >= 0 && n <= 36500 -> do
          Store.init config.db
          StudyStore.migrate config.db
          let i = idOf login
          StudyStore.upsertAccount config.db now Account {githubId = i, login = login, createdGithubUtc = utc (addUTCTime (fromInteger (negate n) * 86400) now)}
          r <- StudyStore.issueKey config.db now i
          case r of
            Right key -> out key >> pure 0
            Left TooManyKeys -> err "the account already has 3 active keys" >> pure 1
        _ -> err usage >> pure 2
  | otherwise = err usage >> pure 2
