-- | The news posts of @site/content/news/@, the same format and the same rules as
-- scripts/news_build.py: a bad post is an error of the build, never a silently shorter page. The
-- patterns are written out by hand, with no regex library.
module Marola.Pages.News
  ( Post (..),
    releases,
    longDate,
    words',
    readingMinutes,
    parsePost,
    build,
    forLanguage,
  )
where

import Data.Char (GeneralCategory (..), generalCategory, isAsciiLower, isDigit, isLetter, isSpace)
import Data.List (sortBy)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Pages.Html (Attr, Node (..))
import Marola.Pages.Html qualified as H
import Marola.Pages.Language (Language (..))
import Marola.Pages.Language qualified as Language
import Marola.Pages.Markdown (collect, inlineNodes)

data Post = Post
  { date :: Text,
    slug :: Text,
    language :: Language,
    -- | The @# @ line as written, for tests and logs.
    title :: Text,
    minutes :: Int,
    article :: Node
  }

releases :: Text
releases = "https://github.com/marola-dev/marola/releases/tag/"

-- A common silent-reading rate for non-fiction; the minutes round up so a short post says 1.
wordsPerMinute :: Int
wordsPerMinute = 200

months :: Language -> [Text]
months PtBr =
  [ "janeiro",
    "fevereiro",
    "março",
    "abril",
    "maio",
    "junho",
    "julho",
    "agosto",
    "setembro",
    "outubro",
    "novembro",
    "dezembro"
  ]
months En =
  [ "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
  ]

readTime :: Language -> Int -> Text
readTime PtBr m = tshow m <> " min de leitura"
readTime En m = tshow m <> " min read"

tshow :: Int -> Text
tshow = T.pack . show

int :: Text -> Int
int = read . T.unpack

longDate :: Language -> Text -> Text -> Text -> Text
longDate l y mo d =
  let month = months l !! (int mo - 1)
   in case l of
        PtBr -> tshow (int d) <> " de " <> month <> " de " <> y
        En -> month <> " " <> tshow (int d) <> ", " <> y

-- A regex \w: letters, non-spacing marks, decimal digits, connector punctuation.
isWordChar :: Char -> Bool
isWordChar c =
  isLetter c || generalCategory c `elem` [NonSpacingMark, DecimalNumber, ConnectorPunctuation]

-- @\]\([^)]*\)|^::: .*$@ in multiline mode, each match replaced by a space.
dropTargets :: Text -> Text
dropTargets = T.pack . go True . T.unpack
  where
    go _ [] = []
    go lineStart s@(c : rest)
      | lineStart, Just after <- stripList "::: " s = ' ' : go False (dropWhile (/= '\n') after)
      | c == ']', '(' : tl <- rest, (_, ')' : after) <- break (== ')') tl = ' ' : go False after
      | otherwise = c : go (c == '\n') rest
    stripList p s = if take (length p) s == p then Just (drop (length p) s) else Nothing

-- | The words a reader reads: no link targets, no Markdown markup.
words' :: [Text] -> [Text]
words' bs =
  let t1 = dropTargets (T.intercalate " " bs)
      t2 = maybe t1 (" " <>) (T.stripPrefix "- " t1)
      t3 = T.map (\c -> if c `elem` ("#*`[]" :: String) then ' ' else c) t2
   in filter (T.any isWordChar) (T.split isSpace (T.strip t3))

readingMinutes :: [Text] -> Int
readingMinutes bs = max 1 ((length (words' bs) + wordsPerMinute - 1) `div` wordsPerMinute)

collapse :: Text -> Text
collapse = T.unwords . T.words

visible :: Node -> Text
visible (TextNode t) = t
visible (El e) = T.concat (map visible (H.children e))

-- Markdown.inlineNodes plus the news rule that a leftover underscore is unrendered Markdown.
inlineOf :: Text -> Either Text [Node]
inlineOf s = do
  nodes <- inlineNodes s
  if T.any (== '_') (T.concat (map visible nodes))
    then Left ("unsupported Markdown in: " <> s)
    else Right nodes

withInline :: Text -> [Attr] -> Text -> Either Text Node
withInline t as s = H.el t as <$> inlineOf s

digits :: Int -> Text -> Maybe (Text, Text)
digits n s =
  let (d, rest) = T.splitAt n s
   in if T.length d == n && T.all isDigit d then Just (d, rest) else Nothing

-- @(\d{4})-(\d{2})-(\d{2})@ then what follows.
isoDate :: Text -> Maybe ((Text, Text, Text), Text)
isoDate s = do
  (y, r1) <- digits 4 s
  r1' <- T.stripPrefix "-" r1
  (mo, r2) <- digits 2 r1'
  r2' <- T.stripPrefix "-" r2
  (d, r3) <- digits 2 r2'
  Just ((y, mo, d), r3)

-- @^::: release (v\d+\.\d+\.\d+) (\d{4})-(\d{2})-(\d{2})$@
releaseLine :: Text -> Maybe (Text, (Text, Text, Text))
releaseLine l = do
  rest <- T.stripPrefix "::: release v" l
  let (version, after) = T.break (== ' ') rest
  case T.splitOn "." version of
    [a, b, c] | all (\p -> not (T.null p) && T.all isDigit p) [a, b, c] -> Just ()
    _ -> Nothing
  dateText <- T.stripPrefix " " after
  (ymd, end) <- isoDate dateText
  if T.null end then Just ("v" <> version, ymd) else Nothing

-- | @::: release vX.Y.Z YYYY-MM-DD@, then @- @ highlights, then one line of links.
releaseCard :: Language -> Text -> Text -> Either Text Node
releaseCard l file blk =
  let lines' = T.splitOn "\n" blk
      first = head lines'
   in case releaseLine first of
        Just (version, (y, mo, d))
          | length lines' >= 2 ->
              let (items, links) = foldr (\x (is, ls) -> if "- " `T.isPrefixOf` x then (x : is, ls) else (is, x : ls)) ([], []) (tail lines')
               in if null items || length links /= 1
                    then Left (file <> ": a release card needs '- ' highlights and one line of links")
                    else do
                      lis <- collect [withInline "li" [] (T.drop 2 i) | i <- items]
                      linkLine <- withInline "p" [H.cls "release-links"] (head links)
                      Right $
                        H.el
                          "aside"
                          [H.cls "release"]
                          [ H.el
                              "p"
                              [H.cls "release-head"]
                              [ H.el
                                  "a"
                                  [H.cls "release-tag", H.attr "href" (releases <> version)]
                                  [H.text ("marola " <> version)],
                                H.text " ",
                                H.el
                                  "time"
                                  [H.attr "datetime" (y <> "-" <> mo <> "-" <> d)]
                                  [H.text (longDate l y mo d)]
                              ],
                            H.el "ul" [] lis,
                            linkLine
                          ]
        _ -> Left (file <> ": '::: release vX.Y.Z YYYY-MM-DD' then its lines: " <> first)

bodyBlock :: Language -> Text -> Text -> Either Text Node
bodyBlock l file blk
  | "## " `T.isPrefixOf` blk && not (T.any (== '\n') blk) = withInline "h2" [] (T.drop 3 blk)
  | "### " `T.isPrefixOf` blk && not (T.any (== '\n') blk) = withInline "h3" [] (T.drop 4 blk)
  | "::: " `T.isPrefixOf` blk = releaseCard l file blk
  | "#" `T.isPrefixOf` blk =
      Left (file <> ": only ## and ### headings inside a post: " <> T.take 40 blk)
  | "- " `T.isPrefixOf` blk =
      H.el "ul" [] <$> collect [withInline "li" [] (collapse i) | i <- T.splitOn "\n- " (T.drop 2 blk)]
  | otherwise = withInline "p" [] (collapse blk)

-- @^(\d{4})-(\d{2})-(\d{2})-([a-z0-9-]+)\.(pt-BR|en)\.md$@
fileName :: Text -> Maybe ((Text, Text, Text), Text, Language)
fileName file = do
  (stem, l) <- case (T.stripSuffix ".pt-BR.md" file, T.stripSuffix ".en.md" file) of
    (Just s, _) -> Just (s, PtBr)
    (_, Just s) -> Just (s, En)
    _ -> Nothing
  (ymd, rest) <- isoDate stem
  s <- T.stripPrefix "-" rest
  if not (T.null s) && T.all (\c -> isAsciiLower c || isDigit c || c == '-') s
    then Just (ymd, s, l)
    else Nothing

-- | One post file: its name decides the date, the slug and the language.
parsePost :: Text -> Text -> Either Text Post
parsePost file txt = case fileName file of
  Nothing -> Left (file <> ": not YYYY-MM-DD-<slug>.<pt-BR|en>.md")
  Just ((y, mo, d), s, l) ->
    let bs = filter (/= "") (map T.strip (T.splitOn "\n\n" (T.replace "\r\n" "\n" txt)))
        iso = y <> "-" <> mo <> "-" <> d
     in case bs of
          ttl : dateLine : lede : rest
            | "# " `T.isPrefixOf` ttl && not (T.any (== '\n') ttl) ->
                if dateLine /= iso
                  then Left (file <> ": the date line must be " <> iso <> ", the file's date")
                  else
                    if "#" `T.isPrefixOf` lede || "- " `T.isPrefixOf` lede
                      then Left (file <> ": the paragraph after the date is the lede")
                      else do
                        let mins = readingMinutes (ttl : lede : rest)
                        heading <- withInline "h2" [] (T.drop 2 ttl)
                        ledeNode <- withInline "p" [H.cls "lede"] (collapse lede)
                        nodes <- collect (map (bodyBlock l file) rest)
                        Right
                          Post
                            { date = iso,
                              slug = s,
                              language = l,
                              title = T.drop 2 ttl,
                              minutes = mins,
                              article =
                                H.el
                                  "article"
                                  [H.cls "about-body", H.attr "lang" (Language.tag l)]
                                  ( [ heading,
                                      H.el
                                        "p"
                                        [H.cls "post-date"]
                                        [ H.el "time" [H.attr "datetime" iso] [H.text (longDate l y mo d)],
                                          H.text (" · " <> readTime l mins)
                                        ],
                                      ledeNode
                                    ]
                                      <> nodes
                                  )
                            }
          _ -> Left (file <> ": needs a '# title', a date line and a lede")

-- | Every post of every language, or why the folder breaks the rules: no post, a post in one
-- language only, a post the README index does not list.
build :: [(Text, Text)] -> Text -> Either Text [Post]
build files index = do
  posts <- collect [parsePost f t | (f, t) <- files]
  let keys l = Set.fromList [(date p, slug p) | p <- posts, language p == l]
      pt = keys PtBr
      en = keys En
  if null posts
    then Left "news: no posts"
    else case Set.toList (Set.union (Set.difference pt en) (Set.difference en pt)) of
      (d, s) : _ -> Left (d <> "-" <> s <> ": needs both a .pt-BR.md and an .en.md")
      [] -> case filter (\(d, s) -> not ((d <> "-" <> s) `T.isInfixOf` index)) (Set.toList pt) of
        (d, s) : _ -> Left (d <> "-" <> s <> ": not listed in news/README.md's index")
        [] -> Right posts

-- | The posts of one language, newest first.
forLanguage :: Language -> [Post] -> [Post]
forLanguage l posts =
  sortBy (\a b -> compare (date b) (date a) <> compare (slug a) (slug b)) (filter ((== l) . language) posts)
