-- | The files the tests read: the repository's own catalogs and page Markdown, and small text
-- helpers in place of regexes.
module Support
  ( root,
    oldPage,
    membersTable,
    loadEnv,
    renderWith,
    has,
    count,
    occurrences,
    between,
    betweenAll,
    htmlDecode,
    visible,
    hrefs,
    attrValues,
  )
where

import Data.Char (chr, isDigit, isHexDigit)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Pages.Language (Language)
import Marola.Pages.Loader (readText)
import Marola.Pages.Loader qualified as Loader
import Marola.Pages.Members qualified as Members
import Marola.Pages.Site (Env)
import Marola.Pages.Site qualified as Site
import Numeric (readHex)
import System.Directory (doesDirectoryExist, getCurrentDirectory)
import System.FilePath (takeDirectory, (</>))

-- | The nearest folder above the working directory that holds the page content.
root :: IO FilePath
root = getCurrentDirectory >>= up
  where
    up dir = do
      found <- doesDirectoryExist (dir </> "site" </> "content" </> "pages")
      if found
        then pure dir
        else
          if takeDirectory dir == dir
            then fail "repository root not found"
            else up (takeDirectory dir)

oldPage :: FilePath -> IO Text
oldPage name = root >>= \r -> readText (r </> "site" </> "static" </> name)

has :: Text -> Text -> Bool
has = T.isInfixOf

count :: Text -> Text -> Int
count needle haystack = length (T.breakOnAll needle haystack)

-- | The text after each occurrence of a needle.
occurrences :: Text -> Text -> [Text]
occurrences needle haystack = map (T.drop (T.length needle) . snd) (T.breakOnAll needle haystack)

-- | @open(.*?)close@, the first match.
between :: Text -> Text -> Text -> Maybe Text
between open close = listToMaybe . betweenAll open close

-- | @open(.*?)close@, every match that does not overlap the one before it.
betweenAll :: Text -> Text -> Text -> [Text]
betweenAll open close s = case T.breakOn open s of
  (_, rest) | T.null rest -> []
  (_, rest) ->
    let (inner, after) = T.breakOn close (T.drop (T.length open) rest)
     in if T.null after then [] else inner : betweenAll open close (T.drop (T.length close) after)

-- | WebUtility.HtmlDecode for what the pages write: the five escapes, @&nbsp;@ and numeric references.
htmlDecode :: Text -> Text
htmlDecode s = case T.breakOn "&" s of
  (before, rest)
    | T.null rest -> before
    | otherwise ->
        let (ref, after) = T.breakOn ";" (T.drop 1 rest)
         in case (decode ref, T.null after) of
              (Just c, False) -> before <> T.singleton c <> htmlDecode (T.drop 1 after)
              _ -> before <> "&" <> htmlDecode (T.drop 1 rest)
  where
    decode r = case T.unpack r of
      "amp" -> Just '&'
      "lt" -> Just '<'
      "gt" -> Just '>'
      "quot" -> Just '"'
      "apos" -> Just '\''
      "nbsp" -> Just '\xA0'
      '#' : x : hex | x `elem` ("xX" :: String), not (null hex), all isHexDigit hex -> Just (chr (fst (head (readHex hex))))
      '#' : dec | not (null dec), all isDigit dec -> Just (chr (read dec))
      _ -> Nothing

-- | What a reader reads: tags dropped, entities decoded, runs of space collapsed.
visible :: Text -> Text
visible = T.unwords . T.words . htmlDecode . dropTags
  where
    dropTags t = case T.breakOn "<" t of
      (before, rest)
        | T.null rest -> before
        | otherwise ->
            let (_, after) = T.breakOn ">" rest
             in if T.null after then before <> rest else before <> " " <> dropTags (T.drop 1 after)

-- | @<tag [^>]*name="([^"]*)"@ for every @<tag @: the value of the attribute in each such tag.
attrValues :: Text -> Text -> Text -> [Text]
attrValues tagName name html = mapMaybe one (occurrences ("<" <> tagName <> " ") html)
  where
    one rest =
      let inTag = T.takeWhile (/= '>') rest
          (before, _) = T.breakOnEnd (name <> "=\"") inTag
       in if T.null before then Nothing else Just (T.takeWhile (/= '"') (T.drop (T.length before) rest))

-- | @<a [^>]*href="([^"]*)"@, decoded.
hrefs :: Text -> [Text]
hrefs = map htmlDecode . attrValues "a" "href"

-- | The repository keeps a pinned copy of MEMBERS.md, but the tests rebuild a table from the old
-- members page: the same people, in the same order, then the non-human rows.
membersTable :: IO Text
membersTable = do
  page <- oldPage "members.html"
  let article = fromMaybe "" (between "<article class=\"about-body\" lang=\"pt-BR\">" "</article>" page)
      lists = betweenAll "<ul class=\"members\">" "</ul>" article
      liBlocks l = drop 1 (T.splitOn "<li class=\"member\">" l)
      people = case lists of l : _ -> liBlocks l; [] -> []
      others = case lists of _ : l : _ -> liBlocks l; _ -> []
      peopleTable = T.intercalate "\n" (header <> map one people)
      nonHuman = case others of
        [] -> ""
        _ -> "\n## Non-human\n\n" <> T.intercalate "\n" (entityTable <> map oneEntity others)
  pure (peopleTable <> nonHuman)
  where
    header = ["| " <> T.intercalate " | " Members.header <> " |", "|" <> T.concat (replicate (length Members.header) "---|")]
    entityTable = ["| " <> T.intercalate " | " Members.entityHeader <> " |", "|---|---|---|"]
    span' c b = maybe "" htmlDecode (listToMaybe [T.takeWhile (/= '<') r | r <- occurrences ("<span class=\"" <> c <> "\">") b, "</span>" `T.isPrefixOf` T.dropWhile (/= '<') r])
    token prefix ok b =
      listToMaybe
        [ v
        | r <- occurrences prefix b,
          let v = T.takeWhile ok r,
          not (T.null v),
          "</a>" `T.isPrefixOf` T.drop (T.length v) r
        ]
    commit b =
      listToMaybe
        [ (url, d)
        | r <- occurrences "<a href=\"" b,
          let url = T.takeWhile (/= '"') r,
          Just afterUrl <- [T.stripPrefix (url <> "\">primeiro commit em ") r],
          let d = T.takeWhile (\c -> isDigit c || c == '-') afterUrl,
          not (T.null d),
          "</a>" `T.isPrefixOf` T.drop (T.length d) afterUrl
        ]
    one b0 =
      let b = fst (T.breakOn "</li>" b0)
          name = span' "member-name" b
          (given, family) = T.breakOnEnd " " name
          role = span' "member-role" b
          (marola, gh) = case T.breakOn "no marola: " role of
            (_, r) | T.null r -> ("", "")
            (_, r) ->
              let (m, g) = T.breakOn " · no GitHub: " (T.drop (T.length ("no marola: " :: Text)) r)
               in (m, T.drop (T.length (" · no GitHub: " :: Text)) g)
          orcid = token "ORCID " (\c -> isDigit c || c == 'X' || c == '-') b
          login = token "@" (\c -> isDigit c || c == '-' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) b
          -- The card's links come in MEMBERS.md's columns, the sites first; stop at ORCID, GitHub or
          -- the commit, whose URLs the other cells name. A site may itself be on github.com.
          stop =
            [ "https://orcid.org/" <> o
            | Just o <- [orcid]
            ]
              <> ["https://github.com/" <> l | Just l <- [login]]
              <> [url | Just (url, _) <- [commit b]]
          websites = takeWhile (`notElem` stop) [T.takeWhile (/= '"') r | r <- occurrences "<a href=\"" b]
       in "| "
            <> T.intercalate
              " | "
              [ family <> ", " <> T.dropEnd 1 given,
                span' "member-aff" b,
                span' "member-state" b,
                maybe "" (\o -> "[" <> o <> "](https://orcid.org/" <> o <> ")") orcid,
                maybe "" (\l -> "[" <> l <> "](https://github.com/" <> l <> ")") login,
                T.unwords websites,
                maybe "" (\(url, d) -> "[" <> d <> "](" <> url <> ")") (commit b),
                marola,
                gh
              ]
            <> " |"
    oneEntity b0 =
      let b = fst (T.breakOn "</li>" b0)
          name = span' "member-name" b
          login = token "@" (\c -> isDigit c || c == '-' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) b
          -- The card's first link is the site; the second is the GitHub login.
          site =
            listToMaybe
              [ url
              | r <- occurrences "<a href=\"" b,
                let url = T.takeWhile (/= '"') r,
                not ("https://github.com/" `T.isPrefixOf` url)
              ]
       in "| "
            <> T.intercalate
              " | "
              [ name,
                maybe "" (\l -> "[" <> l <> "](https://github.com/" <> l <> ")") login,
                fromMaybe "" site
              ]
            <> " |"

loadEnv :: IO Env
loadEnv = do
  r <- root
  table <- membersTable
  Loader.load (r </> "site") table >>= either (fail . T.unpack) pure

renderWith :: Env -> Text -> Language -> Text
renderWith env s l = either (error . T.unpack) id (Site.render env s l)
