-- | A JSON value written by hand: the documents the server sends (the API, the OpenAPI text) keep
-- their key order and their exact escaping, which a JSON library would not promise.
module Marola.Json (Json (..), render, renderText) where

import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as BL
import Data.Char (ord)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE

data Json
  = JNull
  | JBool Bool
  | JInt Int64
  | JString Text
  | JArray [Json]
  | JObject [(Text, Json)]
  deriving (Eq, Show)

-- `<`, `>` and `&` are escaped too, so the body is safe even if a client sniffs it as HTML.
escape :: Text -> Text
escape = T.concatMap one
  where
    one '"' = "\\\""
    one '\\' = "\\\\"
    one '\n' = "\\n"
    one '\t' = "\\t"
    one c
      | c < ' ' || c == '<' || c == '>' || c == '&' || c == '\x2028' || c == '\x2029' = u (ord c)
      | otherwise = T.singleton c
    u n = "\\u" <> T.pack [hex (n `div` 4096), hex (n `div` 256), hex (n `div` 16), hex n]
    hex k = "0123456789abcdef" !! (k `mod` 16)

renderText :: Json -> Text
renderText = TE.decodeUtf8 . BL.toStrict . render

render :: Json -> BL.ByteString
render = B.toLazyByteString . go
  where
    go = \case
      JNull -> "null"
      JBool b -> if b then "true" else "false"
      JInt n -> B.int64Dec n
      JString s -> str s
      JArray items -> "[" <> commas (map go items) <> "]"
      JObject fields -> "{" <> commas [str k <> ":" <> go v | (k, v) <- fields] <> "}"
    str s = "\"" <> TE.encodeUtf8Builder (escape s) <> "\""
    commas [] = mempty
    commas (x : xs) = x <> foldMap ("," <>) xs
