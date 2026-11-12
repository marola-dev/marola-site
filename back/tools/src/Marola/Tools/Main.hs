-- | One executable for the repo's checks and test harnesses, so none of them needs Node (ADR 0007).
module Marola.Tools.Main (main) where

import Marola.Tools.Client (newManager)
import Marola.Tools.DesignCheck qualified as DesignCheck
import Marola.Tools.ElmFixtures qualified as ElmFixtures
import Marola.Tools.FakeGithub qualified as FakeGithub
import Marola.Tools.JsCheck qualified as JsCheck
import Marola.Tools.Net (freePort, waitHttp)
import Marola.Tools.PackageSmoke qualified as PackageSmoke
import Marola.Tools.Smoke qualified as Smoke
import Marola.Tools.SmokeBoard qualified as SmokeBoard
import Marola.Tools.SmokeStudies qualified as SmokeStudies
import Marola.Tools.SmokeSubmit qualified as SmokeSubmit
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.IO (hPutStrLn, stderr)

usage :: String
usage =
  unlines
    [ "usage: marola-tools <command> [args]",
      "  design-check [--self-test]   DESIGN.md against front/public/style.css",
      "  js-check                     every JavaScript file is on scripts/js-allowlist.tsv",
      "  elm-fixtures                 write front/tests/Fixtures.elm for elm-test",
      "  free-port                    print a free port on 127.0.0.1",
      "  wait-http <url> [tries]      exit 0 once the URL answers (200 ms a try, 1 by default)",
      "  fake-github <secret> [port]  a stand-in for GitHub's OAuth flow; prints its port",
      "  smoke <base> <inbox-cmd...>  the server smoke checks",
      "  smoke-studies <base> <key> <pdf> <sha256> <studies-dir>",
      "  smoke-submit <base> <pdf> <sha256>",
      "  smoke-board <base> <id> <sha256> <studies-dir> hidden|purged",
      "  package-smoke <base> <csp.txt> <pid>"
    ]

main :: IO ()
main =
  getArgs >>= \case
    ("design-check" : rest) -> DesignCheck.main rest
    ["js-check"] -> JsCheck.main
    ["elm-fixtures"] -> ElmFixtures.main
    ["free-port"] -> freePort >>= print
    ("wait-http" : url : rest) -> do
      m <- newManager
      up <- waitHttp m url (case rest of (n : _) -> read n; [] -> 1)
      if up then pure () else exitWith (ExitFailure 1)
    ("fake-github" : rest) -> FakeGithub.main rest
    ("smoke" : rest) -> Smoke.main rest
    ("smoke-studies" : rest) -> SmokeStudies.main rest
    ("smoke-submit" : rest) -> SmokeSubmit.main rest
    ("smoke-board" : rest) -> SmokeBoard.main rest
    ("package-smoke" : rest) -> PackageSmoke.main rest
    _ -> hPutStrLn stderr usage >> exitFailure
