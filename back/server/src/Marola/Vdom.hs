-- | A static tree as HTML text: the subset of a virtual DOM the server pages use. Text
-- and attribute values are escaped and there is no raw node, so no study text can add markup.
module Marola.Vdom (Node (..), Attr, el, svg, text, attr, cls, hidden, toHtml) where

import Data.Text (Text)
import Data.Text qualified as T

type Attr = (Text, Text)

data Node
  = Text Text
  | El {svgNs :: Bool, tag :: Text, attrs :: [Attr], children :: [Node]}

el :: Text -> [Attr] -> [Node] -> Node
el = El False

svg :: Text -> [Attr] -> [Node] -> Node
svg = El True

text :: Text -> Node
text = Text

attr :: Text -> Text -> Attr
attr = (,)

cls :: Text -> Attr
cls = ("class",)

-- | The @hidden@ attribute when on, else nothing.
hidden :: Bool -> [Attr]
hidden on = [("hidden", "") | on]

voidTags :: [Text]
voidTags = ["area", "base", "br", "col", "hr", "img", "input", "link", "meta", "source", "wbr"]

escapeText :: Text -> Text
escapeText = T.replace ">" "&gt;" . T.replace "<" "&lt;" . T.replace "&" "&amp;"

escapeAttr :: Text -> Text
escapeAttr = T.replace "\"" "&quot;" . escapeText

toHtml :: Node -> Text
toHtml = \case
  Text t -> escapeText t
  El ns tg as cs ->
    let open = "<" <> tg <> T.concat [" " <> n <> "=\"" <> escapeAttr v <> "\"" | (n, v) <- as]
     in if not ns && tg `elem` voidTags
          then open <> ">"
          else open <> ">" <> T.concat (map toHtml cs) <> "</" <> tg <> ">"
