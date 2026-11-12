-- | The command line: serve, or one of the board's commands. A port of app/Server/Program.fs.
module Marola.Server.Main (main, usage) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (getCurrentTime)
import Marola.Csp qualified as Csp
import Marola.Server.App qualified as App
import Marola.Server.Board qualified as Board
import Marola.Server.Config (Config (..))
import Marola.Server.Config qualified as Config
import Marola.Server.DevAccount qualified as DevAccount
import Marola.Server.Github qualified as Github
import Marola.Server.Inbox qualified as Inbox
import Marola.Server.StudyApi qualified as StudyApi
import Network.Wai.Handler.Warp qualified as Warp
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr, stdout)

usage :: Text
usage =
  "usage: marola-server            serve on 127.0.0.1:$MAROLA_PORT\n       marola-server csp        print the Content-Security-Policy\n       marola-server inbox [--delete <id>]\n       marola-server studies ...   marola-server reports ...   (the board: see docs/6-board.md)\n       marola-server dev-account --login <name> --age-days <n>   (MAROLA_DEV=1, tests only)"

exit :: Int -> IO ()
exit 0 = pure ()
exit n = exitWith (ExitFailure n)

main :: IO ()
main = do
  args <- map T.pack <$> getArgs
  case args of
    -- scripts/site_build.sh writes this to dist/csp.txt, so the page's <meta> and the smoke tests
    -- compare against the header the server sends; it needs no configuration.
    ["csp"] -> TIO.putStr Csp.policy
    _ -> run args

run :: [Text] -> IO ()
run args = do
  config <- Config.fromProcessEnv
  let out = TIO.hPutStrLn stdout
      err = TIO.hPutStrLn stderr
  case config of
    Left message -> err (T.pack message) >> exit 2
    Right cfg -> case args of
      "inbox" : rest -> Inbox.run cfg rest out err >>= exit
      w : _ | w `elem` ["studies", "reports"] -> do
        now <- getCurrentTime
        Board.run cfg now args out err >>= exit
      "dev-account" : rest -> do
        now <- getCurrentTime
        dev <- lookupEnv "MAROLA_DEV"
        DevAccount.run cfg now dev rest out err >>= exit
      [] -> serve cfg
      _ -> err usage >> exit 2

serve :: Config -> IO ()
serve cfg = do
  github <- Github.newHttp
  logger <- App.jsonLogger
  env <- App.newEnv cfg getCurrentTime github logger
  let settings =
        -- nginx faces the world; this port must never be reachable from outside.
        Warp.setHost "127.0.0.1"
          . Warp.setPort cfg.port
          . Warp.setServerName ""
          -- Kestrel reads an unread body to its end before the next request; Warp's default of
          -- 8 KB closes the socket instead, and a browser sending a refused upload sees a reset.
          . Warp.setMaximumBodyFlush (Just (fromIntegral StudyApi.uploadLimit))
          $ Warp.defaultSettings
  Warp.runSettings settings (App.application env)
