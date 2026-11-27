-- | The members page and humans.txt, from marola-dev/.github's MEMBERS.md: the same table, the same
-- rules and the same words as scripts/members_build.py. A row or a header that is wrong is an error
-- of the build, never a silent skip.
module Marola.Pages.Members
  ( Member (..),
    Entity (..),
    header,
    columns,
    entityHeader,
    zenodo,
    file,
    blobId,
    pinnedBlob,
    vendored,
    parse,
    parseEntities,
    initials,
    checkAvatars,
    article,
    humans,
  )
where

import Crypto.Hash.SHA1 qualified as SHA1
import Data.ByteString qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.Char (isAsciiLower, isAsciiUpper, isDigit, toUpper)
import Data.List (partition, sort, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error qualified as TE
import Marola.Pages.Html (Node)
import Marola.Pages.Html qualified as H
import Marola.Pages.Language (Language (..))
import Marola.Pages.Language qualified as Language
import Marola.Pages.Markdown (collect)
import Numeric (showHex)

data Member = Member
  { -- | @Given Family@, from Zenodo's @Family, Given@.
    name :: Text,
    affiliation :: Text,
    -- | The Brazilian state, or the two, the person comes from, as MEMBERS.md spells them; empty
    -- under a header without the column or for a person who did not say.
    state :: Text,
    orcid :: Maybe Text,
    gitHub :: Maybe Text,
    -- | The person's own site or profile, as MEMBERS.md writes it: zero, one or two URLs.
    websites :: [Text],
    -- | The date and the URL of the first commit.
    first :: Maybe (Text, Text),
    -- | Empty under the old headers, which have no role columns.
    marolaRole :: Text,
    gitHubRole :: Text
  }
  deriving (Eq, Show)

-- | The columns in the order MEMBERS.md has them. A header may leave one out (the file had none of
-- State, Website or the roles at some point) but never reorder them: it must be a subsequence.
columns :: [Text]
columns = ["Name", "Affiliation", "State", "ORCID", "GitHub", "Website", "First commit", "marola role", "GitHub role"]

header :: [Text]
header = columns

-- The columns no header may leave out.
required :: [Text]
required = ["Name", "Affiliation", "ORCID", "GitHub", "First commit"]

-- | A people header: every column known, no repeat, the required ones present, and the order
-- @columns@ has them.
headerOk :: [Text] -> Bool
headerOk hd =
  length (Set.toList (Set.fromList hd)) == length hd
    && all (`elem` columns) hd
    && all (`elem` hd) required
    && hd == filter (`elem` hd) columns

-- The 27 states of Brazil, spelled out, as MEMBERS.md writes them.
brazilianStates :: Set.Set Text
brazilianStates =
  Set.fromList
    [ "Acre",
      "Alagoas",
      "Amapá",
      "Amazonas",
      "Bahia",
      "Ceará",
      "Distrito Federal",
      "Espírito Santo",
      "Goiás",
      "Maranhão",
      "Mato Grosso",
      "Mato Grosso do Sul",
      "Minas Gerais",
      "Pará",
      "Paraíba",
      "Paraná",
      "Pernambuco",
      "Piauí",
      "Rio de Janeiro",
      "Rio Grande do Norte",
      "Rio Grande do Sul",
      "Rondônia",
      "Roraima",
      "Santa Catarina",
      "São Paulo",
      "Sergipe",
      "Tocantins"
    ]

-- | One or two Brazilian states, separated by @ / @.
stateOk :: Text -> Bool
stateOk s = case T.splitOn " / " s of
  [one] -> one `Set.member` brazilianStates
  [one, two] -> one `Set.member` brazilianStates && two `Set.member` brazilianStates
  _ -> False

-- | Not a person: an agent or a software fabric, with the site it is known by and the GitHub
-- login whose avatar the card shows.
data Entity = Entity
  { entityName :: Text,
    entityGitHub :: Text,
    entityWebsite :: Text
  }
  deriving (Eq, Show)

entityHeader :: [Text]
entityHeader = ["Name", "GitHub", "Website"]

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
    | Just sha <- T.stripPrefix "blob " second,
      T.length sha == 40,
      T.all isHexLower sha ->
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
  [p1, p2, p3, d] ->
    all (\p -> T.length p == 4 && T.all isDigit p) [p1, p2, p3]
      && T.length d == 4
      && T.all isDigit (T.take 3 d)
      && (let l = T.last d in isDigit l || l == 'X')
  _ -> False

loginOk :: Text -> Bool
loginOk s = T.length s >= 1 && T.length s <= 39 && T.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c == '-') s

-- A person's own site or profile: https, a host with a dot and an alphabetic last label (it is
-- not a login or a number), a path without a space or Markdown noise.
websiteOk :: Text -> Bool
websiteOk u = case T.stripPrefix "https://" u of
  Nothing -> False
  Just rest ->
    let (host, path) = T.breakOn "/" rest
        labels = T.splitOn "." host
        labelOk l =
          not (T.null l)
            && T.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c == '-') l
        top = last labels
     in length labels >= 2
          && all labelOk labels
          && T.length top >= 2
          && T.all (\c -> isAsciiLower c || isAsciiUpper c) top
          && T.all (\c -> c > ' ' && c < '\DEL' && c `notElem` ("|<>`\"\\" :: String)) path

-- | A website as the page shows it: no scheme, no trailing slash.
siteLabel :: Text -> Text
siteLabel url = T.dropWhileEnd (== '/') (fromMaybe url (T.stripPrefix "https://" url))

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
      | not (T.null repo),
        T.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c `elem` ("._-" :: String)) repo,
        T.length sha == 40,
        T.all isHexLower sha ->
          Just (d, url)
    _ -> Nothing

row :: Map Text Int -> [Text] -> Either Text Member
row ix cells =
  let at n = maybe "" (cells !!) (Map.lookup n ix)
      nm = at "Name"
      aff = at "Affiliation"
      st = at "State"
      orcidCell = at "ORCID"
      gh = at "GitHub"
      siteCell = at "Website"
      sites = T.words siteCell
      firstCell = at "First commit"
      withRoles = Map.member "marola role" ix
      (familyPart, givenPart) = T.breakOn ", " nm
      at' = T.length familyPart
      o = selfLink orcidOk "https://orcid.org/" orcidCell
      g = selfLink loginOk "https://github.com/" gh
      c = commitCell firstCell
   in if withRoles && at "marola role" == ""
        then Left (nm <> ": marola role is empty")
        else
          if T.null givenPart || at' < 1 || at' + 2 >= T.length nm
            then Left ("Name is 'Family, Given', as Zenodo writes it: " <> nm)
            else
              if orcidCell /= "" && not (isJust o)
                then Left (nm <> ": ORCID is [id](https://orcid.org/id) or empty: " <> orcidCell)
                else
                  if gh /= "" && not (isJust g)
                    then Left (nm <> ": GitHub is [login](https://github.com/login) or empty: " <> gh)
                    else
                      if st /= "" && not (stateOk st)
                        then Left (nm <> ": State is one or two Brazilian state names separated by ' / ', or empty: " <> st)
                        else
                          if length sites > 2 || not (all websiteOk sites)
                            then
                              Left
                                ( nm
                                    <> ": Website is one or two https:// links separated by a space, or empty: "
                                    <> siteCell
                                )
                            else
                              if firstCell /= "" && not (isJust c)
                                then Left (nm <> ": First commit is [YYYY-MM-DD](commit URL) or empty: " <> firstCell)
                                else
                                  Right
                                    Member
                                      { name = T.drop 2 givenPart <> " " <> familyPart,
                                        affiliation = aff,
                                        state = st,
                                        orcid = o,
                                        gitHub = g,
                                        websites = sites,
                                        first = c,
                                        marolaRole = at "marola role",
                                        gitHubRole = at "GitHub role"
                                      }

-- | MEMBERS.md's tables, each its rows of stripped cells, in the file's order.
tables :: Text -> [[[Text]]]
tables txt = filter (not . null) (reverse (map reverse (finish rows [] [])))
  where
    rows = map T.strip (T.splitOn "\n" txt)
    cells l = map T.strip (T.splitOn "|" (T.dropAround (== '|') l))
    finish [] cur acc = cur : acc
    finish (l : ls) cur acc
      | "|" `T.isPrefixOf` l = finish ls (cells l : cur) acc
      | otherwise = finish ls [] (cur : acc)

-- | MEMBERS.md's table as members, in the file's order.
parse :: Text -> Either Text [Member]
parse txt =
  let wanted = "MEMBERS.md needs one table headed | " <> T.intercalate " | " columns <> " |"
      people = [cs | cs <- tables txt, headerOk (head cs)]
   in case people of
        [] -> Left wanted
        cells : _ -> case cells of
          hd : rule : rows
            | all (T.all (`elem` ("-: " :: String))) rule
                && not (null rows) -> do
                let ix = Map.fromList (zip hd [0 ..])
                members <-
                  collect
                    [ if length cs /= length hd
                        then Left ("a row needs " <> T.pack (show (length hd)) <> " cells: " <> T.intercalate " | " cs)
                        else row ix cs
                    | cs <- rows
                    ]
                let firsts = map (fmap fst . first) members
                    dated = catMaybes firsts
                if dated /= sort dated || take (length dated) firsts /= map Just dated
                  then Left "rows go by first commit, oldest first, then those with none"
                  else Right members
          _ -> Left wanted

-- | MEMBERS.md's @## Non-human@ table as entities, in the file's order; empty when the file has
-- no such table. Each row is an agent or a software fabric, so both the site and the GitHub login
-- (the card's avatar) are required.
parseEntities :: Text -> Either Text [Entity]
parseEntities txt =
  case [cs | cs <- tables txt, head cs == entityHeader] of
    [] -> Right []
    cells : _ -> case cells of
      _ : rule : rows
        | all (T.all (`elem` ("-: " :: String))) rule
            && not (null rows) ->
            collect (map entityRow rows)
      _ -> Left wanted
  where
    wanted = "MEMBERS.md's ## Non-human table needs | " <> T.intercalate " | " entityHeader <> " |"

entityRow :: [Text] -> Either Text Entity
entityRow [nm, gh, site]
  | T.null nm = Left "a non-human row has no name"
  | otherwise = case selfLink loginOk "https://github.com/" gh of
      Nothing ->
        Left (nm <> ": GitHub is [login](https://github.com/login), never empty: " <> gh)
      Just login
        | not (websiteOk site) ->
            Left (nm <> ": Website is one https:// link, never empty: " <> site)
        | otherwise -> Right (Entity nm login site)
entityRow cells = Left ("a non-human row needs three cells: " <> T.intercalate " | " cells)

initials :: Text -> Text
initials nm =
  let parts = filter (not . T.null) (T.split (\c -> c == ' ' || c == '\t') nm)
   in T.map toUpper (T.take 1 (head parts) <> T.take 1 (last parts))

-- | A member's photo file stem: lowercase ASCII, accents folded, hyphens for spaces. It is the
-- name of the optional file under @img/members/@ for a person with no GitHub login.
slug :: Text -> Text
slug nm =
  let parts = T.split (not . ascii) (T.map unaccent (T.toLower nm))
   in T.intercalate "-" (filter (not . T.null) parts)
  where
    ascii c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')

-- | Fold the Portuguese accents a member's name can carry, after @T.toLower@.
unaccent :: Char -> Char
unaccent c = fromMaybe c (lookup c accents)
  where
    accents =
      [ ('á', 'a'),
        ('à', 'a'),
        ('â', 'a'),
        ('ã', 'a'),
        ('ä', 'a'),
        ('é', 'e'),
        ('è', 'e'),
        ('ê', 'e'),
        ('ë', 'e'),
        ('í', 'i'),
        ('ì', 'i'),
        ('î', 'i'),
        ('ï', 'i'),
        ('ó', 'o'),
        ('ò', 'o'),
        ('ô', 'o'),
        ('õ', 'o'),
        ('ö', 'o'),
        ('ú', 'u'),
        ('ù', 'u'),
        ('û', 'u'),
        ('ü', 'u'),
        ('ç', 'c')
      ]

-- | The avatar file of each login must be in the folder, and no other; a person may also have an
-- optional local photo named after them, shown instead of the GitHub avatar. The page never asks
-- GitHub.
checkAvatars :: Map Text Text -> [Member] -> [Entity] -> Either Text ()
checkAvatars avatars members entities =
  let needed = Set.fromList (catMaybes (map gitHub members) <> map entityGitHub entities)
      locals = Set.fromList [slug (name m) | m <- members]
      allowed = needed <> locals
      have = Map.keysSet avatars
   in if needed `Set.isSubsetOf` have && have `Set.isSubsetOf` allowed
        then Right ()
        else
          Left
            ( "img/members/ has avatars for "
                <> T.intercalate ", " (Set.toList have)
                <> ", MEMBERS.md lists "
                <> T.intercalate ", " (Set.toList needed)
                <> " and allows the local photos "
                <> T.intercalate ", " (Set.toList locals)
                <> ": run scripts/members_build.py"
            )

data Copy = Copy
  { cTitle :: Text,
    cLede :: [Node],
    cContributors :: Text,
    cAdvisors :: Text,
    -- | The invisible name of the two-view switch.
    cView :: Text,
    cLofi :: Text,
    cHifi :: Text,
    cCommit :: Text -> Text,
    cRole :: Text -> Text,
    cGitHubRole :: Text -> Text,
    cNonHuman :: Text,
    cNonHumanLede :: [Node],
    cFoot :: [Node]
  }

a :: Text -> [Node] -> Node
a href = H.el "a" [H.attr "href" href]

copy :: Language -> Copy
copy PtBr =
  Copy
    { cTitle = "membros",
      cLede =
        [ H.text "as pessoas que fazem o marola, na ordem do primeiro commit de cada uma nos repositórios do projeto. quem tem ORCID também é autor do ",
          a zenodo [H.text "registro do marola no Zenodo"],
          H.text "."
        ],
      cContributors = "contribuidores",
      cAdvisors = "conselheiros",
      cView = "visão dos membros",
      cLofi = "lo-fi",
      cHifi = "hi-fi",
      cCommit = ("primeiro commit em " <>),
      cRole = ("no marola: " <>),
      cGitHubRole = ("no GitHub: " <>),
      cNonHuman = "não humanos",
      cNonHumanLede = [H.text "não são pessoas: os agentes e as fábricas de software com que o marola é feito."],
      cFoot =
        [ H.text "a lista vem do arquivo ",
          a file [H.el "code" [] [H.text "MEMBERS.md"]],
          H.text " da organização no GitHub. para entrar na lista ou corrigir seus dados, abra um pull request nesse arquivo."
        ]
    }
copy En =
  Copy
    { cTitle = "Members",
      cLede =
        [ H.text "The people who build marola, in the order of their first commit to the project's repositories. Those with an ORCID are also creators of the ",
          a zenodo [H.text "marola record on Zenodo"],
          H.text "."
        ],
      cContributors = "contributors",
      cAdvisors = "advisors",
      cView = "members view",
      cLofi = "lo-fi",
      cHifi = "hi-fi",
      cCommit = ("first commit on " <>),
      cRole = ("marola: " <>),
      cGitHubRole = ("GitHub: " <>),
      cNonHuman = "non-human",
      cNonHumanLede = [H.text "Not people: the agents and software fabrics marola is built with."],
      cFoot =
        [ H.text "The list comes from the organization's ",
          a file [H.el "code" [] [H.text "MEMBERS.md"]],
          H.text " on GitHub. To join it or fix your details, open a pull request on that file."
        ]
    }
copy Ja =
  Copy
    { cTitle = "メンバー",
      cLede =
        [ H.text "marolaを作っている人々。プロジェクトのリポジトリでの最初のコミット順に並んでいます。ORCIDを持つ人は ",
          a zenodo [H.text "marolaのZenodo登録"],
          H.text " の著者でもあります。"
        ],
      cContributors = "コントリビューター",
      cAdvisors = "アドバイザー",
      cView = "メンバー表示",
      cLofi = "lo-fi",
      cHifi = "hi-fi",
      cCommit = ("最初のコミット: " <>),
      cRole = ("marolaでの役割: " <>),
      cGitHubRole = ("GitHubでの役割: " <>),
      cNonHuman = "人間以外",
      cNonHumanLede = [H.text "人ではありません。marolaを作るエージェントとソフトウェアファクトリーです。"],
      cFoot =
        [ H.text "この一覧はGitHubの組織の ",
          a file [H.el "code" [] [H.text "MEMBERS.md"]],
          H.text " から来ています。載るには、そのファイルにpull requestを開いてください。"
        ]
    }
copy ZhHant =
  Copy
    { cTitle = "成員",
      cLede =
        [ H.text "打造 marola 的人，依各自在專案儲存庫首次提交的順序排列。有 ORCID 的人也是 ",
          a zenodo [H.text "marola 的 Zenodo 登錄"],
          H.text " 的作者。"
        ],
      cContributors = "貢獻者",
      cAdvisors = "顧問",
      cView = "成員檢視",
      cLofi = "lo-fi",
      cHifi = "hi-fi",
      cCommit = ("首次提交於 " <>),
      cRole = ("marola 的角色: " <>),
      cGitHubRole = ("GitHub 的角色: " <>),
      cNonHuman = "非人類",
      cNonHumanLede = [H.text "不是人：打造 marola 的代理與軟體工廠。"],
      cFoot =
        [ H.text "這份名單來自 GitHub 組織的 ",
          a file [H.el "code" [] [H.text "MEMBERS.md"]],
          H.text "。要加入或更正資料，請對該檔案提出合併請求。"
        ]
    }

span' :: Text -> [Node] -> Node
span' c = H.el "span" [H.cls c]

-- Absolute, so /en/members.html reaches the same files as /members.html.
avatarNode :: Text -> Node
avatarNode f =
  H.el
    "img"
    [ H.cls "member-mark",
      H.attr "src" ("/img/members/" <> f),
      H.attr "width" "48",
      H.attr "height" "48",
      H.attr "alt" "",
      H.attr "loading" "lazy"
    ]
    []

-- | The links of a card, separated by a space.
joined :: [Node] -> [Node]
joined [] = []
joined (x : xs) = x : concatMap (\n -> [H.text " ", n]) xs

-- | The lo-fi line: the name alone, one line per person.
lofiItem :: Member -> Node
lofiItem m =
  H.el "li" [H.cls "member-lofi"] [span' "member-lofi-name" [H.text (name m)]]

item :: Copy -> Map Text Text -> Member -> Node
item c avatars m =
  H.el
    "li"
    [H.cls "member"]
    ( [mark, span' "member-name" [H.text (name m)]]
        <> [span' "member-aff" [H.text (affiliation m)] | affiliation m /= ""]
        <> [span' "member-state" [H.text (state m)] | state m /= ""]
        <> [span' "member-role" [H.text (T.intercalate " · " roles)] | not (null roles)]
        <> [span' "member-links" links | not (null links)]
    )
  where
    mark = case Map.lookup (slug (name m)) avatars of
      Just f -> avatarNode f
      Nothing -> case gitHub m >>= (`Map.lookup` avatars) of
        Just f -> avatarNode f
        Nothing -> H.el "span" [H.cls "member-mark", H.attr "aria-hidden" "true"] [H.text (initials (name m))]
    linkNodes =
      [a url [H.text (siteLabel url)] | url <- websites m]
        <> catMaybes
          [ (\i -> a ("https://orcid.org/" <> i) [H.text ("ORCID " <> i)]) <$> orcid m,
            (\l -> a ("https://github.com/" <> l) [H.text ("@" <> l)]) <$> gitHub m,
            (\(d, url) -> a url [H.text (cCommit c d)]) <$> first m
          ]
    links = joined linkNodes
    -- The roles are MEMBERS.md's words, shown as they are written there.
    roles = [cRole c (marolaRole m) | marolaRole m /= ""] <> [cGitHubRole c (gitHubRole m) | gitHubRole m /= ""]

-- | The card of an entity: its GitHub avatar, its name, then its site and its GitHub login.
entityItem :: Map Text Text -> Entity -> Node
entityItem avatars e =
  H.el
    "li"
    [H.cls "member"]
    [ mark,
      span' "member-name" [H.text (entityName e)],
      span' "member-links" links
    ]
  where
    mark = case Map.lookup (entityGitHub e) avatars of
      Just f -> avatarNode f
      Nothing -> H.el "span" [H.cls "member-mark", H.attr "aria-hidden" "true"] [H.text (T.take 1 (entityName e))]
    links =
      joined
        [ a (entityWebsite e) [H.text (siteLabel (entityWebsite e))],
          a ("https://github.com/" <> entityGitHub e) [H.text ("@" <> entityGitHub e)]
        ]

-- | One section of the list, in both views: the lo-fi lines and the hi-fi cards. The stylesheet
-- shows one of them, never both.
memberSection :: Copy -> Map Text Text -> Text -> [Member] -> Node
memberSection c avatars title ms =
  H.el
    "section"
    [H.cls "members-group"]
    ( [H.el "h2" [] [H.text title]]
        <> [H.el "ul" [H.cls "members-lofi"] (map lofiItem ms) | not (null ms)]
        <> [H.el "ul" [H.cls "members"] (map (item c avatars) ms) | not (null ms)]
    )

-- | Advising order: PV first, Yuri second, then the rest in MEMBERS.md's order (a stable sort).
advisorRank :: Member -> Int
advisorRank m = case slug (name m) of
  "pedro-veras-guimaraes" -> 0
  "yuri-kuzniecow" -> 1
  _ -> 2

-- | Contributors in MEMBERS.md's order; advisors by 'advisorRank'.
groups :: [Member] -> ([Member], [Member])
groups members =
  let (advisors, contributors) = partition ((== "advisor") . marolaRole) members
   in (contributors, sortOn advisorRank advisors)

-- | The two mutually exclusive views, as a radio group: no script, the stylesheet does the switching.
viewSwitch :: Copy -> [Node]
viewSwitch c =
  [ H.el
      "input"
      [ H.cls "members-view-input",
        H.attr "type" "radio",
        H.attr "name" "members-view",
        H.attr "id" "members-lofi",
        H.attr "checked" ""
      ]
      [],
    H.el
      "input"
      [ H.cls "members-view-input",
        H.attr "type" "radio",
        H.attr "name" "members-view",
        H.attr "id" "members-hifi"
      ]
      [],
    H.el
      "div"
      [H.cls "members-view-switch", H.attr "role" "group", H.attr "aria-label" (cView c)]
      [ H.el "label" [H.attr "for" "members-lofi"] [H.text (cLofi c)],
        H.el "label" [H.attr "for" "members-hifi"] [H.text (cHifi c)]
      ]
  ]

-- | The @<article>@ of the page in one language.
article :: Language -> Map Text Text -> [Member] -> [Entity] -> Node
article l avatars members entities =
  let c = copy l
      (contributors, advisors) = groups members
      memberSections =
        [memberSection c avatars (cContributors c) contributors | not (null contributors)]
          <> [memberSection c avatars (cAdvisors c) advisors | not (null advisors)]
      nonHuman =
        [ H.el "h2" [] [H.text (cNonHuman c)],
          H.el "p" [H.cls "lede"] (cNonHumanLede c),
          H.el "ul" [H.cls "members"] (map (entityItem avatars) entities)
        ]
      section = if null entities then [] else nonHuman
   in H.el
        "article"
        [H.cls "about-body", H.attr "lang" (Language.tag l)]
        ( [ H.el "h2" [] [H.text (cTitle c)],
            H.el "p" [H.cls "lede"] (cLede c)
          ]
            <> viewSwitch c
            <> memberSections
            <> section
            <> [H.el "p" [] (cFoot c)]
        )

-- | humanstxt.org's plain format, one block per member in MEMBERS.md's order.
humans :: [Member] -> Text
humans members =
  T.intercalate "\n" lines' <> "\n"
  where
    lines' =
      [ "/* TEAM */",
        "# Generated by back/pages (marola-pages) from marola-dev/.github's MEMBERS.md; do not edit.",
        ""
      ]
        <> concatMap block members
        <> [ "/* SITE */",
             "Members: " <> file,
             "Cite: " <> zenodo,
             "Code: https://github.com/marola-dev/marola-site",
             "Language: Português (Brasil), English",
             "Standards: HTML, CSS, Elm compiled to JavaScript, Haskell on the server",
             "Components: MapLibre GL JS, Inter"
           ]
    block m =
      ["Name: " <> name m]
        <> ["Role: " <> marolaRole m | marolaRole m /= ""]
        <> ["Affiliation: " <> affiliation m | affiliation m /= ""]
        <> ["State: " <> state m | state m /= ""]
        <> maybe [] (\l -> ["GitHub: https://github.com/" <> l]) (gitHub m)
        <> maybe [] (\i -> ["ORCID: https://orcid.org/" <> i]) (orcid m)
        <> ["Website: " <> u | u <- websites m]
        <> [""]
