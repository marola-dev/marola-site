-- | The ICU message subset the catalogs use: @{arg}@, @{n, plural, ...}@ with @#@, and
-- @{x, select, ...}@. A port of app/Shared/Icu.fs for the pages, which pass text arguments only:
-- a number argument and its locale formatting stay in the client.
module Marola.Pages.Icu (IcuNode (..), parse, format) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

data IcuNode
  = Literal Text
  | Hash
  | Argument Text (Maybe Text) (Map Text [IcuNode])
  deriving (Eq, Show)

-- | JavaScript's @\\s@.
isJsSpace :: Char -> Bool
isJsSpace c =
  c `elem` (" \t\n\r\x0B\x0C\xA0\x1680\x2028\x2029\x202F\x205F\x3000\xFEFF" :: String)
    || (c >= '\x2000' && c <= '\x200A')

type P a = Text -> Either Text (a, Text)

fail' :: Text -> Text -> Either Text b
fail' rest expected = Left ("i18n: expected " <> expected <> " near " <> T.take 20 rest)

skipSpaces :: Text -> Text
skipSpaces = T.dropWhile isJsSpace

word :: P Text
word input =
  let s = skipSpaces input
      (name, after) = T.break (\c -> isJsSpace c || c == ',' || c == '{' || c == '}') s
   in if T.null name then fail' input "a name" else Right (name, skipSpaces after)

expect :: Char -> Text -> Either Text Text
expect c s = case T.uncons s of
  Just (x, rest) | x == c -> Right rest
  _ -> fail' s (T.singleton c)

message :: Bool -> P [IcuNode]
message inPlural = loop [] ""
  where
    flush out buf = if T.null buf then out else Literal buf : out
    loop out buf s = case T.uncons s of
      Nothing -> Right (reverse (flush out buf), s)
      Just ('}', _) -> Right (reverse (flush out buf), s)
      Just ('{', rest) -> do
        (node, after) <- argument inPlural rest
        loop (node : flush out buf) "" after
      Just ('#', rest) | inPlural -> loop (Hash : flush out buf) "" rest
      Just _ ->
        let (chunk, rest) = T.span (\c -> c /= '}' && c /= '{' && not (inPlural && c == '#')) s
         in loop out (buf <> chunk) rest

argument :: Bool -> P IcuNode
argument inPlural s0 = do
  (name, s1) <- word s0
  case T.uncons s1 of
    Just (',', s2) -> do
      (kind, s3) <- word s2
      s4 <- expect ',' s3
      (cs, s5) <- cases (inPlural || kind == "plural") Map.empty (skipSpaces s4)
      s6 <- expect '}' s5
      Right (Argument name (Just kind) cs, s6)
    _ -> do
      s2 <- expect '}' s1
      Right (Argument name Nothing Map.empty, s2)

cases :: Bool -> Map Text [IcuNode] -> P (Map Text [IcuNode])
cases inPlural acc s = case T.uncons s of
  Nothing -> Right (acc, s)
  Just ('}', _) -> Right (acc, s)
  _ -> do
    (key, s1) <- word s
    s2 <- expect '{' s1
    (nodes, s3) <- message inPlural s2
    s4 <- expect '}' s3
    cases inPlural (Map.insert key nodes acc) (skipSpaces s4)

parse :: Text -> Either Text [IcuNode]
parse src = do
  (nodes, rest) <- message False src
  if T.null rest then Right nodes else Left ("i18n: unbalanced } in " <> src)

-- | The first of the keys the message has, else its @other@ case.
firstCase :: Map Text [IcuNode] -> [Text] -> [IcuNode]
firstCase cs keys = case [n | k <- keys, Just n <- [Map.lookup k cs]] of
  n : _ -> n
  [] -> fromMaybe [] (Map.lookup "other" cs)

-- | With text arguments only, a plural never has a number: it takes @other@ and @#@ prints NaN,
-- as Intl does for a value that is not one.
format :: [IcuNode] -> [(Text, Text)] -> Text
format nodes args = T.concat (map one nodes)
  where
    one (Literal t) = t
    one Hash = "NaN"
    one (Argument name Nothing _) = fromMaybe ("{" <> name <> "}") (lookup name args)
    one (Argument name (Just "plural") cs) =
      format (firstCase cs ["=" <> keyOf name, "other"]) args
    one (Argument name (Just _) cs) = format (firstCase cs [keyOf name]) args
    keyOf name = fromMaybe "undefined" (lookup name args)
