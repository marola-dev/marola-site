-- | Fails when DESIGN.md and front/public/style.css drift apart.
--
--   1. Every custom property defined in @:root@ has a row in a DESIGN.md token table.
--   2. Every token row in DESIGN.md is defined in @:root@, with the same value.
--   3. style.css holds no hex colour outside @:root@, except the 'allow' list.
--
-- A token row is a row of a table whose header starts with "Token". Its first cell is one backticked
-- @--name@ and its second cell is the backticked value, exactly as @:root@ writes it (whitespace
-- collapsed). Other tables (the contrast table) may name a token in their first cell and are not read.
module Marola.Tools.DesignCheck (check, main, selfTest) where

import Data.ByteString qualified as B
import Data.Char (isAlphaNum, isHexDigit, isSpace, toLower)
import Data.List (nub)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import System.Exit (exitFailure)

-- | Hex colours that may stay outside @:root@, each with its reason. The check also fails when an
-- entry no longer occurs, so this list can only shrink. It is empty since the ink redraw.
allow :: [(Text, Text)]
allow = []

stripComments :: Text -> Text
stripComments css = case T.breakOn "/*" css of
  (before, rest)
    | T.null rest -> before
    | otherwise -> case T.breakOn "*/" (T.drop 2 rest) of
        (_, end) | T.null end -> before
        (_, end) -> before <> stripComments (T.drop 2 end)

norm :: Text -> Text
norm = T.unwords . T.words

-- | The @:root@ block and the css without it.
splitRoot :: Text -> (Maybe Text, Text)
splitRoot css = case findRoot 0 css of
  Nothing -> (Nothing, css)
  Just start ->
    let afterStart = T.drop start css
        (beforeOpen, fromOpen) = T.breakOn "{" afterStart
        open = start + T.length beforeOpen
        (block, fromClose) = T.breakOn "}" (T.drop 1 fromOpen)
        close = open + 1 + T.length block
     in if T.null fromClose
          then (Just block, T.take start css)
          else (Just block, T.take start css <> T.drop (close + 1) css)
  where
    findRoot offset t = case T.breakOn ":root" t of
      (_, rest) | T.null rest -> Nothing
      (before, rest) ->
        let at = offset + T.length before
            after = T.dropWhile isSpace (T.drop 5 rest)
         in if "{" `T.isPrefixOf` after then Just at else findRoot (at + 5) (T.drop 5 rest)

rootTokens :: Text -> [(Text, Text)]
rootTokens css = case fst (splitRoot (stripComments css)) of
  Nothing -> []
  Just block -> dedupe (concatMap decl (T.splitOn ";" block))
  where
    decl d =
      let d' = T.dropWhile isSpace d
          (name, rest) = T.span (\c -> isAlphaNum c && c < '\x80' || c == '-') d'
       in if "--" `T.isPrefixOf` name && T.length name > 2
            then case T.uncons (T.dropWhile isSpace rest) of
              Just (':', value) -> [(name, norm value)]
              _ -> []
            else []
    -- A later declaration wins, at the place of the first one (a JavaScript Map's set).
    dedupe pairs = [(n, last [v | (n', v) <- pairs, n' == n]) | n <- nub (map fst pairs)]

data Row = Row {rowName :: Text, rowValue :: Maybe Text}

docTokens :: Text -> [Row]
docTokens md = go False False (T.splitOn "\n" md)
  where
    go _ _ [] = []
    go inTable previousWasRow (line : rest)
      | not ("|" `T.isPrefixOf` line) = go False False rest
      | otherwise =
          let cells = map T.strip (dropLast (drop 1 (T.splitOn "|" line)))
              inTable' = if previousWasRow then inTable else take 1 cells == ["Token"]
              row = do
                name <- tokenName =<< cellAt 0 cells
                Just (Row name (fmap norm (backticked =<< cellAt 1 cells)))
           in [r | inTable', Just r <- [row]] <> go inTable' True rest
    dropLast xs = take (length xs - 1) xs
    cellAt i cs = case drop i cs of
      (c : _) -> Just c
      [] -> Nothing
    backticked c
      | T.length c >= 3 && "`" `T.isPrefixOf` c && "`" `T.isSuffixOf` c = Just (T.drop 1 (T.dropEnd 1 c))
      | otherwise = Nothing
    tokenName c = do
      inner <- backticked c
      if "--" `T.isPrefixOf` inner && T.length inner > 2 && T.all (\x -> isAlphaNum x && x < '\x80' || x == '-') inner
        then Just inner
        else Nothing

-- | Each hex colour outside @:root@, lowercased, with its count, in the order first seen. A colour
-- follows a colon, a space, a comma or a bracket; a selector like @#app@ has no hex-only name.
hexOutsideRoot :: Text -> [(Text, Int)]
hexOutsideRoot css = counts (scan (T.unpack (snd (splitRoot (stripComments css)))))
  where
    scan (p : '#' : rest)
      | p == ':' || p == ',' || p == '(' || isSpace p =
          let (digits, after) = span isHexDigit rest
              n = length digits
              word c = isAlphaNum c || c == '_' || c == '-'
              ends = case after of
                (c : _) -> not (word c)
                [] -> True
           in if n >= 3 && n <= 8 && ends
                then T.pack ('#' : map toLower digits) : scan ('#' : rest)
                else scan ('#' : rest)
    scan (_ : rest) = scan rest
    scan [] = []
    counts xs = [(x, length (filter (== x) xs)) | x <- nub xs]

check :: Text -> Text -> [(Text, Text)] -> [Text]
check md css allowed =
  [ "undocumented token: " <> name <> " is in :root, not in a DESIGN.md table"
  | (name, _) <- root,
    name `notElem` map rowName rows
  ]
    <> concat (zipWith rowFailures [0 :: Int ..] rows)
    <> [ "hex outside :root: " <> colour <> " (" <> tshow count <> "x) in style.css; use a token or add it to ALLOW with a reason"
       | (colour, count) <- hex,
         isNothing (lookup colour allowed)
       ]
    <> [ "unused allowlist entry: " <> colour <> " no longer occurs in style.css; remove it"
       | (colour, _) <- allowed,
         isNothing (lookup colour hex)
       ]
  where
    root = rootTokens css
    rows = docTokens md
    hex = hexOutsideRoot css
    rowFailures i row =
      [ "duplicate row: " <> rowName row <> " appears twice in DESIGN.md"
      | rowName row `elem` map rowName (take i rows)
      ]
        <> case (lookup (rowName row) root, rowValue row) of
          (Nothing, _) -> ["unknown token: " <> rowName row <> " is in DESIGN.md, not in :root"]
          (Just _, Nothing) -> ["no value: the DESIGN.md row of " <> rowName row <> " has no backticked value"]
          (Just inRoot, Just value)
            | value /= inRoot -> ["value differs: " <> rowName row <> " is `" <> value <> "` in DESIGN.md and `" <> inRoot <> "` in :root"]
            | otherwise -> []
    tshow = T.pack . show

-- | The three rules on bad fixtures: each one must fail, and a good pair must pass.
selfTest :: IO Bool
selfTest = do
  let css = ":root { --ink: #111820; --bg: #fff; /* c */ --sh: 0 1px 2px rgb(0 0 0 / .1), 0 2px 4px red; }\n#app { color: var(--ink); }\n"
      md =
        T.intercalate
          "\n"
          [ "| Token | Value | Job |",
            "|---|---|---|",
            "| `--ink` | `#111820` | text |",
            "| `--bg` | `#fff` | page |",
            "| `--sh` | `0 1px 2px rgb(0 0 0 / .1), 0 2px 4px red` | shadow |"
          ]
      withoutBg = T.intercalate "\n" (filter (not . T.isPrefixOf "| `--bg`") (T.splitOn "\n" md))
      cases :: [(Text, Text, Text, [(Text, Text)], Maybe Text)]
      cases =
        [ ("a good pair passes", md, css, [], Nothing),
          ("a table that is not headed Token is not read", md <> "\n\n| Text | On |\n|---|---|\n| `--ink` | `--bg` |\n", css, [], Nothing),
          ("rule 1: a token missing from DESIGN.md", withoutBg, css, [], Just "undocumented token: --bg"),
          ("rule 2: a token missing from :root", md <> "\n| `--gone` | `1px` | x |", css, [], Just "unknown token: --gone"),
          ("rule 2: a different value", T.replace "#111820" "#111821" md, css, [], Just "value differs: --ink"),
          ("rule 2: a row with no value", T.replace "`#111820`" "#111820" md, css, [], Just "no value: the DESIGN.md row of --ink"),
          ("rule 3: a hex outside :root", md, css <> ".a { color: #abc; }\n", [], Just "hex outside :root: #abc"),
          ("rule 3: a hex in a media query", md, css <> "@media (max-width: 1px) { .a { background: #A1B2C3; } }\n", [], Just "hex outside :root: #a1b2c3"),
          ("rule 3: an allowed hex passes", md, css <> ".a { color: #abc; }\n", [("#abc", "test")], Nothing),
          ("rule 3: an unused allowlist entry", md, css, [("#abc", "test")], Just "unused allowlist entry: #abc")
        ]
  bad <- fmap concat . mapM run $ cases
  if null bad
    then TIO.putStrLn ("design_check self-test: ok (" <> T.pack (show (length cases)) <> " cases)") >> pure True
    else mapM_ TIO.putStrLn bad >> pure False
  where
    run (label, m, c, allowed, expect) = do
      let out = check m c allowed
          ok = maybe (null out) (\e -> any (e `T.isInfixOf`) out) expect
      pure ["design_check self-test: " <> label <> ": expected " <> maybe "no failure" id expect <> ", got " <> T.pack (show out) | not ok]

main :: [String] -> IO ()
main args
  | "--self-test" `elem` args = selfTest >>= \ok -> if ok then pure () else exitFailure
  | otherwise = do
      md <- TE.decodeUtf8 <$> B.readFile "DESIGN.md"
      css <- TE.decodeUtf8 <$> B.readFile "front/public/style.css"
      let failures = check md css allow
      mapM_ (TIO.putStrLn . ("design_check: " <>)) failures
      if null failures then TIO.putStrLn "design_check: ok" else exitFailure
