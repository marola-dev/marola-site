-- | The build: MEMBERS.md, the pages and the metadata files into an output folder.
module Marola.Pages.Build (main, membersText, today) where

import Control.Exception (SomeException, try)
import qualified Data.ByteString as B
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import Data.Time.Calendar (Day)
import Data.Time.Clock (getCurrentTime, utctDay)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Marola.Pages.Loader (readText)
import qualified Marola.Pages.Loader as Loader
import qualified Marola.Pages.Members as Members
import qualified Marola.Pages.Meta as Meta
import qualified Marola.Pages.Site as Site
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (takeDirectory, (</>))
import System.IO (hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)

usage :: String
usage = "usage: marola-pages <site-dir> <out-dir>"

-- MEMBERS.md lives in marola-dev/.github. The repo keeps a copy at site/members/MEMBERS.md, and
-- site/members.version names the commit it came from and its blob id, so a build needs no network.
-- MEMBERS_SOURCE names another local copy and takes precedence. With neither file, the build fetches
-- the commit (with curl, which keeps the binary free of a TLS stack).
membersText :: FilePath -> IO (Either Text Text)
membersText site = do
  local <- lookupEnv "MEMBERS_SOURCE"
  version <- readText (site </> "members.version")
  let vendoredPath = site </> "members" </> "MEMBERS.md"
  hasVendored <- doesFileExist vendoredPath
  case local of
    Just p | p /= "" -> do
      exists <- doesFileExist p
      if exists then Right <$> readText p else pure (Left ("MEMBERS_SOURCE is not a file: " <> T.pack p))
    _
      | hasVendored -> Members.vendored version <$> B.readFile vendoredPath
      | otherwise -> do
          let sha = T.strip (head (T.splitOn "\n" version))
              url = "https://raw.githubusercontent.com/marola-dev/.github/" <> sha <> "/MEMBERS.md"
              failed why = Left ("cannot fetch " <> url <> " (set MEMBERS_SOURCE to a local MEMBERS.md): " <> why)
          r <- try (readProcessWithExitCode "curl" ["-fsSL", "--max-time", "30", T.unpack url] "")
          pure $ case r :: Either SomeException (ExitCode, String, String) of
            Left e -> failed (T.pack (show e))
            Right (ExitSuccess, out, _) -> Right (T.pack out)
            Right (_, _, err) -> failed (T.strip (T.pack err))

-- | The build's date in UTC. MAROLA_PAGES_TODAY (YYYY-MM-DD) fixes it, so a reproducible build
-- or a parity check against an older output writes the same security.txt.
today :: IO (Either Text Day)
today = do
  fixed <- lookupEnv "MAROLA_PAGES_TODAY"
  case fixed of
    Just s | s /= "" -> pure $ maybe (Left ("MAROLA_PAGES_TODAY is not YYYY-MM-DD: " <> T.pack s)) Right (parseTimeM False defaultTimeLocale "%Y-%m-%d" s)
    _ -> Right . utctDay <$> getCurrentTime

main :: IO ()
main = do
  args <- getArgs
  case args of
    [site, outDir] -> do
      members <- membersText site
      envE <- either (pure . Left) (Loader.load site) members
      day <- today
      let built = do
            env <- envE
            d <- day
            pages <- Site.allPages env
            files <- Meta.files env d
            Right (pages <> files)
      case built of
        Left message -> do
          B.hPut stderr (TE.encodeUtf8 ("pages: " <> message <> "\n"))
          exitWith (ExitFailure 1)
        Right pages -> do
          mapM_
            ( \(f, txt) -> do
                let target = outDir </> T.unpack f
                createDirectoryIfMissing True (takeDirectory target)
                B.writeFile target (TE.encodeUtf8 txt)
            )
            pages
          TIO.putStrLn ("pages: " <> T.pack (show (length pages)) <> " files in " <> T.pack outDir)
    _ -> do
      hPutStrLn stderr usage
      exitWith (ExitFailure 2)
