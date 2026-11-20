-- | The checks of scripts/package_smoke.sh: the Nix package's server answers the pages and the study
-- API with 200 and the CSP header, which is csp.txt (the page's policy) plus form-action.
module Marola.Tools.PackageSmoke (main) where

import Control.Monad (forM, unless)
import Data.ByteString qualified as B
import Data.Char (isDigit)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Marola.Tools.Client
import Marola.Tools.Net (waitHttp)
import System.Exit (exitFailure)

main :: [String] -> IO ()
main = \case
  [base, cspFile, pid] -> do
    m <- newManager
    csp <- T.strip . TE.decodeUtf8 <$> B.readFile cspFile
    up <- waitHttp m (base <> "/") 100
    unless up (fail "the server did not start")
    results <- forM ["/", "/about.html", "/en/studies", "/api/v1/skill.md"] $ \p -> do
      r <- get m base (TE.encodeUtf8 p)
      let same = maybe False (csp `T.isPrefixOf`) (hdr "content-security-policy" r)
          good = r.status == 200 && same
      TIO.putStrLn ("package_smoke: " <> (if good then "ok   " else "FAIL ") <> T.pack (show r.status) <> " " <> p <> (if same then "" else " (no CSP header, or not csp.txt's policy)"))
      pure good
    status <- TE.decodeUtf8 <$> B.readFile ("/proc/" <> pid <> "/status")
    let kb = [T.takeWhile isDigit (T.strip rest) | l <- T.lines status, Just rest <- [T.stripPrefix "VmRSS:" l]]
        mb = case kb of
          (k : _) | not (T.null k) -> T.pack (show (round (read (T.unpack k) / 1024 :: Double) :: Int))
          _ -> "?"
    TIO.putStrLn ("package_smoke: resident set after the requests: " <> fromMaybe "?" (Just mb) <> " MB")
    unless (and results) exitFailure
  _ -> fail "usage: marola-tools package-smoke <base> <csp.txt> <pid>"
