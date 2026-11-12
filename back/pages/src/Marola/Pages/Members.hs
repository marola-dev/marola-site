-- | The members page and humans.txt, from marola-dev/.github's MEMBERS.md: the same table, the same
-- rules and the same words as scripts/members_build.py. A row or a header that is wrong is an error
-- of the build, never a silent skip. A port of app/Pages/Members.fs.
module Marola.Pages.Members
  ( Member (..)
  , header
  , legacy
  , zenodo
  , file
  , blobId
  , pinnedBlob
  , vendored
  , parse
  , initials
  , checkAvatars
  , article
  , humans
  ) where

import qualified Crypto.Hash.SHA1 as SHA1
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import Data.Char (isAsciiLower, isAsciiUpper, isDigit, toUpper)
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, isJust)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Encoding.Error as TE
import Marola.Pages.Html (Node)
import qualified Marola.Pages.Html as H
import Marola.Pages.Language (Language (..))
import qualified Marola.Pages.Language as Language
import Marola.Pages.Markdown (collect)
import Numeric (showHex)

data Member = Member
  { name :: Text
  -- ^ @Given Family@, from Zenodo's @Family, Given@.
  , affiliation :: Text
  , orcid :: Maybe Text
  , gitHub :: Maybe Text
  , first :: Maybe (Text, Text)
  -- ^ The date and the URL of the first commit.
  , marolaRole :: Text
  -- ^ Empty under the old header, which has no role columns.
  , gitHubRole :: Text
  }
  deriving (Eq, Show)

header :: [Text]
header = ["Name", "Affiliation", "ORCID", "GitHub", "First commit", "marola role", "GitHub role"]

-- The header before the two role columns (MEMBERS.md, 14 October 2026): accepted until it moves.
legacy :: [Text]
legacy = take 5 header

zenodo :: Text
zenodo = "https://doi.org/10.5281/zenodo.23224155"

file :: Text
file = "https://github.com/marola-dev/.github/blob/main/MEMBERS.md"

-- | The git blob id of a file's bytes: what @git hash-object@ prints.
blobId :: B.ByteString -> Text
blobId bytes =
  let digest = SHA1.hash (BC.pack ("blob " <> show (B.length bytes) <> "\0") <> bytes)
   in T.pack (concatMap (\w -> let h = showHex w "" in if length h == 1 then '0' : h else h) (B.unpack digest))

isHexLower :: Char -> Bool
isHexLower c = isDigit c || (c >= 'a' && c <= 'f')

-- | The blob id on the second line of site/members.version ("blob <sha>"), if the pin has one.
pinnedBlob :: Text -> Maybe Text
pinnedBlob version = case map T.strip (T.splitOn "\n" version) of
  _ : second : _
    | Just sha <- T.stripPrefix "blob " second
    , T.length sha == 40
    , T.all isHexLower sha ->
        Just sha
  _ -> Nothing

-- | The vendored MEMBERS.md as text, when its bytes are the blob the pin names. A copy that drifted
-- from the pin is an error, never a silent switch to another source.
vendored :: Text -> B.ByteString -> Either Text Text
vendored version bytes = case pinnedBlob version of
  Nothing -> Left "site/members.version has no second line 'blob <sha>' for site/members/MEMBERS.md"
  Just pinned
    | blobId bytes /= pinned ->
        Left ("site/members/MEMBERS.md is blob " <> blobId bytes <> " but site/members.version pins " <> pinned)
  Just _ -> Right (TE.decodeUtf8With TE.lenientDecode bytes)

-- `[inner](prefix<inner>)` where inner passes the check; the link names the same id.
selfLink :: (Text -> Bool) -> Text -> Text -> Maybe Text
selfLink ok prefix cell = do
  rest <- T.stripPrefix "[" cell
  let (inner, after) = T.breakOn "]" rest
  if ok inner && after == "](" <> prefix <> inner <> ")" then Just inner else Nothing

orcidOk :: Text -> Bool
orcidOk s = case T.splitOn "-" s of
  [a, b, c, d] ->
    all (\p -> T.length p == 4 && T.all isDigit p) [a, b, c]
      && T.length d == 4
      && T.all isDigit (T.take 3 d)
      && (let l = T.last d in isDigit l || l == 'X')
  _ -> False

loginOk :: Text -> Bool
loginOk s = T.length s >= 1 && T.length s <= 39 && T.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c == '-') s

-- `[YYYY-MM-DD](https://github.com/marola-dev/<repo>/commit/<40 hex>)`
commitCell :: Text -> Maybe (Text, Text)
commitCell cell = do
  rest <- T.stripPrefix "[" cell
  let (d, after) = T.breakOn "](" rest
  url <- T.stripPrefix "](" after >>= T.stripSuffix ")"
  case T.splitOn "-" d of
    [y, m, dd] | T.length y == 4 && T.length m == 2 && T.length dd == 2 && T.all isDigit (y <> m <> dd) -> Just ()
    _ -> Nothing
  repoAndSha <- T.stripPrefix "https://github.com/marola-dev/" url
  case T.splitOn "/commit/" repoAndSha of
    [repo, sha]
      | not (T.null repo)
      , T.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c `elem` ("._-" :: String)) repo
      , T.length sha == 40
      , T.all isHexLower sha ->
          Just (d, url)
    _ -> Nothing

row :: Bool -> [Text] -> Either Text Member
row full cells =
  let (nm, aff, orcidCell, gh, firstCell) = (cells !! 0, cells !! 1, cells !! 2, cells !! 3, cells !! 4)
      (familyPart, givenPart) = T.breakOn ", " nm
      at = T.length familyPart
      o = selfLink orcidOk "https://orcid.org/" orcidCell
      g = selfLink loginOk "https://github.com/" gh
      c = commitCell firstCell
   in if full && cells !! 5 == ""
        then Left (nm <> ": marola role is empty")
        else
          if T.null givenPart || at < 1 || at + 2 >= T.length nm
            then Left ("Name is 'Family, Given', as Zenodo writes it: " <> nm)
            else
              if orcidCell /= "" && not (isJust o)
                then Left (nm <> ": ORCID is [id](https://orcid.org/id) or empty: " <> orcidCell)
                else
                  if gh /= "" && not (isJust g)
                    then Left (nm <> ": GitHub is [login](https://github.com/login) or empty: " <> gh)
                    else
                      if firstCell /= "" && not (isJust c)
                        then Left (nm <> ": First commit is [YYYY-MM-DD](commit URL) or empty: " <> firstCell)
                        else
                          Right
                            Member
                              { name = T.drop 2 givenPart <> " " <> familyPart
                              , affiliation = aff
                              , orcid = o
                              , gitHub = g
                              , first = c
                              , marolaRole = if full then cells !! 5 else ""
                              , gitHubRole = if full then cells !! 6 else ""
                              }

-- | MEMBERS.md's table as members, in the file's order.
parse :: Text -> Either Text [Member]
parse txt =
  let cells =
        [ map T.strip (T.splitOn "|" (T.dropAround (== '|') l))
        | l <- map T.strip (T.splitOn "\n" txt)
        , "|" `T.isPrefixOf` l
        ]
      wanted = "MEMBERS.md needs one table headed | " <> T.intercalate " | " header <> " |"
   in case cells of
        hd : rule : rows
          | (hd == header || hd == legacy)
              && all (T.all (`elem` ("-: " :: String))) rule
              && not (null rows) -> do
              let full = hd == header
              members <-
                collect
                  [ if length cs /= length hd
                      then Left ("a row needs " <> T.pack (show (length hd)) <> " cells: " <> T.intercalate " | " cs)
                      else row full cs
                  | cs <- rows
                  ]
              let firsts = map (fmap fst . first) members
                  dated = catMaybes firsts
              if dated /= sort dated || take (length dated) firsts /= map Just dated
                then Left "rows go by first commit, oldest first, then those with none"
                else Right members
        _ -> Left wanted

initials :: Text -> Text
initials nm =
  let parts = filter (not . T.null) (T.split (\c -> c == ' ' || c == '\t') nm)
   in T.map toUpper (T.take 1 (head parts) <> T.take 1 (last parts))

-- | The avatar file of each login must be in the folder, and no other: the page never asks GitHub.
checkAvatars :: Map Text Text -> [Member] -> Either Text ()
checkAvatars avatars members =
  let logins = Set.fromList (catMaybes (map gitHub members))
      have = Map.keysSet avatars
   in if logins == have
        then Right ()
        else
          Left
            ( "img/members/ has avatars for "
                <> T.intercalate ", " (Set.toList have)
                <> ", MEMBERS.md lists "
                <> T.intercalate ", " (Set.toList logins)
                <> ": run scripts/members_build.py"
            )

data Copy = Copy
  { cTitle :: Text
  , cLede :: [Node]
  , cCommit :: Text -> Text
  , cRole :: Text -> Text
  , cGitHubRole :: Text -> Text
  , cFoot :: [Node]
  }

a :: Text -> [Node] -> Node
a href = H.el "a" [H.attr "href" href]

copy :: Language -> Copy
copy PtBr =
  Copy
    { cTitle = "membros"
    , cLede =
        [ H.text "as pessoas que fazem o marola, na ordem do primeiro commit de cada uma nos repositórios do projeto. quem tem ORCID também é autor do "
        , a zenodo [H.text "registro do marola no Zenodo"]
        , H.text "."
        ]
    , cCommit = ("primeiro commit em " <>)
    , cRole = ("no marola: " <>)
    , cGitHubRole = ("no GitHub: " <>)
    , cFoot =
        [ H.text "a lista vem do arquivo "
        , a file [H.el "code" [] [H.text "MEMBERS.md"]]
        , H.text " da organização no GitHub. para entrar na lista ou corrigir seus dados, abra um pull request nesse arquivo."
        ]
    }
copy En =
  Copy
    { cTitle = "Members"
    , cLede =
        [ H.text "The people who build marola, in the order of their first commit to the project's repositories. Those with an ORCID are also creators of the "
        , a zenodo [H.text "marola record on Zenodo"]
        , H.text "."
        ]
    , cCommit = ("first commit on " <>)
    , cRole = ("marola: " <>)
    , cGitHubRole = ("GitHub: " <>)
    , cFoot =
        [ H.text "The list comes from the organization's "
        , a file [H.el "code" [] [H.text "MEMBERS.md"]]
        , H.text " on GitHub. To join it or fix your details, open a pull request on that file."
        ]
    }

span' :: Text -> [Node] -> Node
span' c = H.el "span" [H.cls c]

item :: Copy -> Map Text Text -> Member -> Node
item c avatars m =
  H.el
    "li"
    [H.cls "member"]
    ( [mark, span' "member-name" [H.text (name m)]]
        <> [span' "member-aff" [H.text (affiliation m)] | affiliation m /= ""]
        <> [span' "member-role" [H.text (T.intercalate " · " roles)] | not (null roles)]
        <> [span' "member-links" links | not (null links)]
    )
  where
    mark = case gitHub m >>= (`Map.lookup` avatars) of
      -- Absolute, so /en/members.html reaches the same files as /members.html.
      Just f ->
        H.el
          "img"
          [ H.cls "member-mark"
          , H.attr "src" ("/img/members/" <> f)
          , H.attr "width" "48"
          , H.attr "height" "48"
          , H.attr "alt" ""
          , H.attr "loading" "lazy"
          ]
          []
      Nothing -> H.el "span" [H.cls "member-mark", H.attr "aria-hidden" "true"] [H.text (initials (name m))]
    linkNodes =
      catMaybes
        [ (\i -> a ("https://orcid.org/" <> i) [H.text ("ORCID " <> i)]) <$> orcid m
        , (\l -> a ("https://github.com/" <> l) [H.text ("@" <> l)]) <$> gitHub m
        , (\(d, url) -> a url [H.text (cCommit c d)]) <$> first m
        ]
    links = case linkNodes of
      [] -> []
      x : xs -> x : concatMap (\n -> [H.text " ", n]) xs
    -- The roles are MEMBERS.md's words, shown as they are written there.
    roles = [cRole c (marolaRole m) | marolaRole m /= ""] <> [cGitHubRole c (gitHubRole m) | gitHubRole m /= ""]

-- | The @<article>@ of the page in one language.
article :: Language -> Map Text Text -> [Member] -> Node
article l avatars members =
  let c = copy l
   in H.el
        "article"
        [H.cls "about-body", H.attr "lang" (Language.tag l)]
        [ H.el "h2" [] [H.text (cTitle c)]
        , H.el "p" [H.cls "lede"] (cLede c)
        , H.el "ul" [H.cls "members"] (map (item c avatars) members)
        , H.el "p" [] (cFoot c)
        ]

-- | humanstxt.org's plain format, one block per member in MEMBERS.md's order.
humans :: [Member] -> Text
humans members =
  T.intercalate "\n" lines' <> "\n"
  where
    lines' =
      [ "/* TEAM */"
      , "# Generated by app/Pages.Build from marola-dev/.github's MEMBERS.md; do not edit."
      , ""
      ]
        <> concatMap block members
        <> [ "/* SITE */"
           , "Members: " <> file
           , "Cite: " <> zenodo
           , "Code: https://github.com/marola-dev/marola-front"
           , "Language: Português (Brasil), English"
           , "Standards: HTML, CSS, F# compiled to JavaScript; no framework"
           , "Components: MapLibre GL JS, Inter"
           ]
    block m =
      ["Name: " <> name m]
        <> ["Role: " <> marolaRole m | marolaRole m /= ""]
        <> ["Affiliation: " <> affiliation m | affiliation m /= ""]
        <> maybe [] (\l -> ["GitHub: https://github.com/" <> l]) (gitHub m)
        <> maybe [] (\i -> ["ORCID: https://orcid.org/" <> i]) (orcid m)
        <> [""]
