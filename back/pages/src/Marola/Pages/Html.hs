-- | The node tree the pages are made of and its HTML text: the map page's
-- @Vdom.toHtml@ rules. Text and attribute values are escaped and there is no
-- raw node, so no message can add markup. Tags and attribute names come from code, never from data.
module Marola.Pages.Html
  ( Attr (..),
    Node (..),
    Element (..),
    svgNs,
    el,
    svg,
    text,
    attr,
    cls,
    hidden,
    toHtml,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

data Attr = Attr Text Text | Flag Text Bool
  deriving (Eq, Show)

data Node = TextNode Text | El Element
  deriving (Eq, Show)

data Element = Element
  { ns :: Text,
    tag :: Text,
    attrs :: [Attr],
    children :: [Node]
  }
  deriving (Eq, Show)

svgNs :: Text
svgNs = "http://www.w3.org/2000/svg"

el :: Text -> [Attr] -> [Node] -> Node
el t as cs = El (Element "" t as cs)

svg :: Text -> [Attr] -> [Node] -> Node
svg t as cs = El (Element svgNs t as cs)

text :: Text -> Node
text = TextNode

attr :: Text -> Text -> Attr
attr = Attr

cls :: Text -> Attr
cls = Attr "class"

-- | The @hidden@ attribute when on, else nothing.
hidden :: Bool -> [Attr]
hidden on = [Attr "hidden" "" | on]

voidTags :: [Text]
voidTags = ["area", "base", "br", "col", "hr", "img", "input", "link", "meta", "source", "wbr"]

escapeText :: Text -> Text
escapeText = T.replace ">" "&gt;" . T.replace "<" "&lt;" . T.replace "&" "&amp;"

escapeAttr :: Text -> Text
escapeAttr = T.replace "\"" "&quot;" . escapeText

attrHtml :: Attr -> Text
attrHtml (Attr n v) = " " <> n <> "=\"" <> escapeAttr v <> "\""
attrHtml (Flag n True) = " " <> n
attrHtml (Flag _ False) = ""

toHtml :: Node -> Text
toHtml (TextNode t) = escapeText t
toHtml (El e)
  | ns e == "" && tag e `elem` voidTags = open <> ">"
  | otherwise = open <> ">" <> T.concat (map toHtml (children e)) <> "</" <> tag e <> ">"
  where
    open = "<" <> tag e <> T.concat (map attrHtml (attrs e))
