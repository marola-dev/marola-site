-- | The small Markdown that the pages need, the same subset as scripts/news_build.py plus a few block
-- forms: @::lede@, @> @ quotes, @![alt](/src WxH)@ figures and @{{soon name|label}}@. Anything else
-- that looks like markup is an error, so a page never goes out half-rendered.
-- scripts/pages_parity.sh checks that its output does not change byte for byte.
module Marola.Pages.Markdown
  ( Doc (..),
    linkOk,
    inlineNodes,
    collect,
    parse,
  )
where

import Data.Char (isAsciiLower, isDigit)
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Pages.Html (Attr, Node)
import Marola.Pages.Html qualified as H

data Doc = Doc {title :: Text, description :: Text, body :: [Node]}

-- A bare `about.html` is a sibling page: it resolves under `/` and under `/en/` to the page of the
-- same language, which the news posts rely on.
sibling :: Text -> Bool
sibling url = case T.stripSuffix ".html" url of
  Just name -> not (T.null name) && T.all (\c -> isAsciiLower c || isDigit c || c == '-') name
  Nothing -> False

linkOk :: Text -> Bool
linkOk url =
  ( "https://" `T.isPrefixOf` url
      || "http://" `T.isPrefixOf` url
      || ("/" `T.isPrefixOf` url && not ("//" `T.isPrefixOf` url))
      || "#" `T.isPrefixOf` url
      || sibling url
  )
    && not (T.any (== ' ') url)
    && not (T.any (== '"') url)

-- | Inline markup: `code`, **bold**, [text](url) and {{soon name|label}}.
inlineNodes :: Text -> Either Text [Node]
inlineNodes whole = go [] "" whole
  where
    fail' what = Left (what <> ": " <> whole)
    flush out buf = if T.null buf then out else H.text buf : out
    go out buf s
      | T.null s = Right (reverse (flush out buf))
      | Just rest <- T.stripPrefix "`" s =
          closed "`" rest "unclosed `" $ \inner after ->
            go (H.el "code" [] [H.text inner] : flush out buf) "" after
      | Just rest <- T.stripPrefix "**" s =
          closed "**" rest "unclosed **" $ \inner after ->
            go (H.el "b" [] [H.text inner] : flush out buf) "" after
      | Just rest <- T.stripPrefix "[" s =
          closed "](" rest "unclosed [" $ \label after ->
            closed ")" after "unclosed (" $ \url after2 ->
              if linkOk url && label /= "" && not (T.any (== '[') label)
                then go (H.el "a" [H.attr "href" url] [H.text label] : flush out buf) "" after2
                else fail' ("bad link " <> url)
      | Just rest <- T.stripPrefix "{{soon " s =
          closed "}}" rest "unclosed {{" $ \inner after ->
            case T.splitOn "|" inner of
              [name, label] ->
                let node =
                      H.el
                        "span"
                        [H.attr "aria-disabled" "true"]
                        [H.text (name <> " "), H.el "i" [] [H.text label]]
                 in go (node : flush out buf) "" after
              _ -> fail' "{{soon name|label}}"
      | "*" `T.isPrefixOf` s || "]" `T.isPrefixOf` s || "{{" `T.isPrefixOf` s = fail' "unsupported markup"
      | otherwise = go out (T.snoc buf (T.head s)) (T.tail s)
    closed needle rest what k =
      let (inner, after) = T.breakOn needle rest
       in if T.null after then fail' what else k inner (T.drop (T.length needle) after)

-- | The first error, else every value in order.
collect :: [Either e a] -> Either e [a]
collect = sequence

withInline :: Text -> [Attr] -> Text -> Either Text Node
withInline t as s = H.el t as <$> inlineNodes s

strip :: Text -> Text -> Text
strip prefix = T.drop (T.length prefix)

-- The last occurrence of a needle, as the text before it and the text after it.
breakOnEndMaybe :: Text -> Text -> Maybe (Text, Text)
breakOnEndMaybe needle s =
  let (before, after) = T.breakOnEnd needle s
   in if T.null before then Nothing else Just (T.dropEnd (T.length needle) before, after)

-- `![alt](/src WxH)` then the caption lines.
figure :: [Text] -> Either Text Node
figure [] = Left "bad figure"
figure lines'@(first : _) =
  case breakOnEndMaybe "](" first of
    Nothing -> bad
    Just _ | not (")" `T.isSuffixOf` first) -> bad
    Just (before, after) ->
      let alt = T.drop 2 before
          spec = T.splitOn " " (T.dropEnd 1 after)
       in case spec of
            [src, size]
              | linkOk src && T.any (== 'x') size ->
                  let parts = T.splitOn "x" size
                      (w, h) = (head parts, parts !! 1)
                   in fmap
                        ( \caption ->
                            H.el
                              "figure"
                              []
                              [ H.el
                                  "a"
                                  [H.attr "href" src]
                                  [ H.el
                                      "img"
                                      [ H.attr "src" src,
                                        H.attr "width" w,
                                        H.attr "height" h,
                                        H.attr "alt" alt
                                      ]
                                      []
                                  ],
                                H.el "figcaption" [] caption
                              ]
                        )
                        (inlineNodes (T.intercalate " " (drop 1 lines')))
            _ -> bad
  where
    bad = Left ("bad figure: " <> first)

-- `> @en` sets the language of the quote, `> -- ` is the source line, other lines are paragraphs.
quote :: [Text] -> Either Text Node
quote lines' =
  let (lang, rest) = case lines' of
        first : tl | "> @" `T.isPrefixOf` first -> ([H.attr "lang" (strip "> @" first)], tl)
        _ -> ([], lines')
      line l
        | "> -- " `T.isPrefixOf` l = withInline "footer" [] (strip "> -- " l)
        | "> " `T.isPrefixOf` l = withInline "p" [] (strip "> " l)
        | otherwise = Left ("bad quote line: " <> l)
   in H.el "blockquote" lang <$> collect (map line rest)

block :: [Text] -> Either Text (Maybe Node)
block [] = Right Nothing
block lines'@(first : _)
  | "%% " `T.isPrefixOf` first = Right Nothing
  | "## " `T.isPrefixOf` first = some (withInline "h2" [] (strip "## " first))
  | "### " `T.isPrefixOf` first = some (withInline "h3" [] (strip "### " first))
  | "#" `T.isPrefixOf` first = Left ("unsupported heading: " <> first)
  | "- " `T.isPrefixOf` first =
      some (H.el "ul" [] <$> collect (map item lines'))
  | "> " `T.isPrefixOf` first = some (quote lines')
  | "![" `T.isPrefixOf` first = some (figure lines')
  | "::lede " `T.isPrefixOf` first =
      some (withInline "p" [H.cls "lede"] (strip "::lede " (T.intercalate " " lines')))
  | "<" `T.isPrefixOf` first = Left ("raw HTML is not supported: " <> first)
  | otherwise = some (withInline "p" [] (T.intercalate " " lines'))
  where
    some = fmap Just
    item l
      | "- " `T.isPrefixOf` l = withInline "li" [] (strip "- " l)
      | otherwise = Left ("a list item that wraps: " <> l)

-- | Blocks: groups of lines apart by a blank line.
blocks :: Text -> [[Text]]
blocks src = finish (foldl step ([], []) (T.splitOn "\n" (T.replace "\r\n" "\n" src)))
  where
    step (done, current) l
      | T.strip l == "" = (if null current then done else reverse current : done, [])
      | otherwise = (done, T.stripEnd l : current)
    finish (done, current) = reverse (if null current then done else reverse current : done)

-- | @title:@ and @description:@ lines, a blank line, then the body.
parse :: Text -> Either Text Doc
parse src = case blocks src of
  [] -> Left "empty page"
  hd : rest ->
    let field name = listToMaybe (mapMaybe (T.stripPrefix (name <> ": ")) hd)
     in case (field "title", field "description") of
          (Just t, Just d)
            | length hd == 2 ->
                (\nodes -> Doc t d (concatMap (maybe [] pure) nodes)) <$> collect (map block rest)
          _ -> Left "a page starts with the lines 'title: ' and 'description: '"
