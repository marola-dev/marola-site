-- | What the board's commands did, seen from outside: a hidden study shows its tombstone and never
-- serves its file; after a purge the file is gone from disk too.
module Marola.Tools.SmokeBoard (main) where

import Control.Monad (unless)
import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as V
import Marola.Tools.Client
import System.Directory (doesFileExist)
import System.Exit (exitFailure)

main :: [String] -> IO ()
main = \case
  [base, sid, sha, studiesDir, mode] | mode `elem` ["hidden", "purged"] -> do
    m <- newManager
    c <- newChecks ""
    let check cond what = ok c cond what ""
        tag = "[" <> T.pack mode <> "] "
        g = get m base . TE.encodeUtf8 . T.pack
        shaT = T.pack sha
    page <- g ("/studies/" <> sid)
    let html = text page
    check (page.status == 200 && shaT `T.isInfixOf` html) (tag <> "the tombstone page shows the hash")
    check ("smoke: " `T.isInfixOf` html && not ("Smoke test of the study API" `T.isInfixOf` html)) (tag <> "the tombstone shows the board's reason and no study text")
    pdf <- g ("/studies/" <> sid <> ".pdf")
    check (pdf.status == 404) (tag <> "the file is not served")
    api <- json <$> g ("/api/v1/studies/" <> sid)
    let noTitle = case api of
          A.Object o -> not (KM.member "title" o)
          _ -> True
    check (str (field "status" api) == Just "hidden" && str (field "sha256" api) == Just shaT && noTitle) (tag <> "the API answers a tombstone with the hash and no text")
    listed <- json <$> g "/api/v1/studies"
    let ids = case field "studies" listed of
          A.Array xs -> [str (field "id" s) | s <- V.toList xs]
          _ -> []
    check (Just (T.pack sid) `notElem` ids) (tag <> "the study left the list")
    onDisk <- doesFileExist (studiesDir <> "/" <> sha <> ".pdf")
    if mode == "hidden"
      then check onDisk "the hidden study's file is still on disk"
      else check (not onDisk) "the purge removed the file from disk"
    n <- failures c
    unless (n == 0) exitFailure
  _ -> fail "usage: marola-tools smoke-board <base> <id> <sha256> <studies-dir> hidden|purged"
