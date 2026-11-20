-- | The hard rule of ADR 0007: every JavaScript file git tracks is on scripts/js-allowlist.tsv with
-- the reason it cannot be Elm or Haskell. A file that is not listed fails, and so does an entry that
-- matches no file, so the list can only shrink. An entry ending in @/@ covers a vendored folder.
module Marola.Tools.JsCheck (Entry (..), check, isJavaScript, main, parse) where

import Data.ByteString qualified as B
import Data.List (isPrefixOf, isSuffixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import System.Exit (exitFailure)
import System.Process (readProcess)

data Entry = Entry {path :: String, reason :: Text}
  deriving (Eq, Show)

allowlist :: FilePath
allowlist = "scripts/js-allowlist.tsv"

isJavaScript :: String -> Bool
isJavaScript p = any (`isSuffixOf` p) [".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx"]

-- | Tab-separated: the path, then the reason. Blank lines and lines starting with @#@ are skipped.
parse :: Text -> Either Text [Entry]
parse = traverse entry . filter keep . zip [1 :: Int ..] . T.lines
  where
    keep (_, l) = not (T.null (T.strip l)) && not ("#" `T.isPrefixOf` l)
    entry (n, l) = case T.splitOn "\t" l of
      [p, r] | not (T.null (T.strip p)), T.length (T.strip r) >= 10 -> Right (Entry (T.unpack (T.strip p)) (T.strip r))
      _ -> Left (allowlistT <> ":" <> T.pack (show n) <> ": want <path><TAB><reason of ten characters or more>")
    allowlistT = T.pack allowlist

covers :: Entry -> String -> Bool
covers e f
  | "/" `isSuffixOf` path e = path e `isPrefixOf` f
  | otherwise = path e == f

check :: [Entry] -> [String] -> [Text]
check entries files =
  [ "not allowed: " <> T.pack f <> " is JavaScript and not on " <> T.pack allowlist <> "; write it in Elm or Haskell (ADR 0007)"
  | f <- files,
    isJavaScript f,
    not (any (`covers` f) entries)
  ]
    <> [ "unused entry: " <> T.pack (path e) <> " matches no file; remove it"
       | e <- entries,
         not (any (covers e) files)
       ]

main :: IO ()
main = do
  listed <- parse . TE.decodeUtf8 <$> B.readFile allowlist
  files <- lines <$> readProcess "git" ["ls-files"] ""
  case listed of
    Left err -> TIO.putStrLn ("js_check: " <> err) >> exitFailure
    Right entries -> do
      let failures = check entries files
          kept = length (filter isJavaScript files)
      mapM_ (TIO.putStrLn . ("js_check: " <>)) failures
      if null failures
        then TIO.putStrLn ("js_check: ok (" <> T.pack (show kept) <> " JavaScript files, each on the allowlist with its reason)")
        else exitFailure
