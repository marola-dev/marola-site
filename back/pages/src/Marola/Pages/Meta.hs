-- | The files that are not pages: robots.txt, sitemap.xml, llms.txt, humans.txt and
-- .well-known/security.txt. A port of app/Pages/Meta.fs (the rules of scripts/site_meta.py).
module Marola.Pages.Meta
  ( expiresDays
  , robots
  , llms
  , dynamicSlugs
  , sitemap
  , securityTxt
  , files
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Calendar (Day, addDays, showGregorian)
import Marola.Pages.Language (Language (..))
import qualified Marola.Pages.Layout as Layout
import qualified Marola.Pages.Members as Members
import Marola.Pages.Site (Area (..), Env (..))
import qualified Marola.Pages.Site as Site

baseUrl :: Text
baseUrl = Layout.origin

-- The pages a crawler should index, in nav order; contact carries noindex, so it is in llms.txt (a
-- person may want it) but not in the sitemap.
llmsPages :: [(Text, Text, Text)]
llmsPages =
  [ ("", "The map", "every beach in an area, ranked by the best hour to swim today and tomorrow")
  , ("about.html", "About", "what marola is, why it is open and non-profit, how it works, the data")
  , ("news.html", "News", "releases, how the project is built and what is in progress")
  , ("members.html", "Members", "who builds marola, the same people as the Zenodo record")
  , ("support.html", "Support", "how to donate, where the money goes and how to check the accounts")
  , ("contact.html", "Contact", "a form whose message reaches the team's e-mail")
  , ("privacy.html", "Privacy", "what marola stores about authors and visitors, what it does not, and what you can do")
  , ("takedown.html", "Takedown", "how to ask for a study to be removed and what the board does")
  ]

securityPolicy :: Text
securityPolicy = "https://github.com/marola-dev/.github/blob/main/SECURITY.md"

-- Under a year, as RFC 9116 section 2.5.5 recommends; the live check fails once it has passed.
expiresDays :: Integer
expiresDays = 364

robots :: Text
robots =
  "# marola.dev: every page and every board is public. Cloudflare prepends its managed content\n"
    <> "# signals above this block; what they say is a zone setting (docs/3-development.md).\n"
    <> "User-agent: *\n"
    <> "Allow: /\n\n"
    <> "Sitemap: "
    <> baseUrl
    <> "/sitemap.xml\n"

llms :: [Area] -> Text
llms areas =
  T.intercalate "\n" lines' <> "\n"
  where
    names = T.intercalate ", " (map areaName areas)
    lines' =
      [ "# marola"
      , ""
      , "> marola.dev is an open, non-profit map of the Brazilian coast built as citizen science."
          <> " For each area it ranks every beach by the best hour to swim today and tomorrow, from"
          <> " OpenStreetMap beaches, Open-Meteo sea and weather data and the state agencies' official"
          <> " bathing-water reports, with a 0–100 score and a deterministic safety veto. The boards are"
          <> " precomputed and no LLM runs when you open a page. This site's code is MIT."
      , ""
      , "Areas: "
          <> names
          <> ". The pages are in Portuguese (pt-BR) at the root and in English under `/en/`; the map"
          <> " takes `?lang=en`."
      , ""
      , "Things to know before answering from this site:"
      , ""
      , "- A score is an estimate. The official water report wins over it, and the safety veto is"
          <> " not advice to swim."
      , "- \"No data\" means the source returned nothing, not that the water is clean."
      , "- The boards are rebuilt when a person runs the build; each area's `latest.json` says when"
          <> " (`generated_at`) and which days it covers."
      , "- Each board names its sources (`sources`); their own terms apply to the data."
      , ""
      , "## Pages"
      , ""
      ]
        <> ["- [" <> t <> "](" <> baseUrl <> "/" <> p <> "): " <> w | (p, t, w) <- llmsPages]
        <> [ ""
           , "## Data"
           , ""
           , "- [Areas](" <> baseUrl <> "/data/areas.json): every area with its centre, radius and board index"
           ]
        <> [ "- ["
              <> areaName a
              <> "]("
              <> baseUrl
              <> "/data/"
              <> areaId a
              <> "/latest.json): the days published for `"
              <> areaId a
              <> "`, each a board file next to it"
           | a <- areas
           ]
        <> [ "- [Board contract](" <> baseUrl <> "/board.schema.json): the JSON Schema every board follows"
           , ""
           , "## API"
           , ""
           , "- [openapi.json](" <> baseUrl <> "/api/v1/openapi.json): OpenAPI 3.1 of the study API (submit, list, read)"
           , "- [skill.md](" <> baseUrl <> "/api/v1/skill.md): the same API as a guide for agents, with examples"
           , ""
           , "## Docs"
           , ""
           , "- [docs.marola.dev](https://docs.marola.dev/): the project's documentation, every repo"
           , "- [docs.marola.dev/llms.txt](https://docs.marola.dev/llms.txt): the same for the docs and"
              <> " the code"
           , "- [Code](https://github.com/marola-dev/marola-site): this site; the rest is under"
              <> " https://github.com/marola-dev"
           , "- [How to cite](" <> Members.zenodo <> "): the marola record on Zenodo"
           , ""
           , "## Optional"
           , ""
           , "- [security.txt](" <> baseUrl <> "/.well-known/security.txt): how to report a vulnerability"
           , "- [humans.txt](" <> baseUrl <> "/humans.txt): the team, from the org's MEMBERS.md"
           ]

-- | The pages the server renders and the sitemap lists.
dynamicSlugs :: [Text]
dynamicSlugs = ["submit", "studies"]

-- | Every page a crawler may index, in both languages, each with the three alternates; the map once.
sitemap :: Text
sitemap =
  T.intercalate "\n" lines' <> "\n"
  where
    entry loc pt en =
      [ "  <url>"
      , "    <loc>" <> loc <> "</loc>"
      , "    <xhtml:link rel=\"alternate\" hreflang=\"pt-BR\" href=\"" <> pt <> "\"/>"
      , "    <xhtml:link rel=\"alternate\" hreflang=\"en\" href=\"" <> en <> "\"/>"
      , "    <xhtml:link rel=\"alternate\" hreflang=\"x-default\" href=\"" <> pt <> "\"/>"
      , "  </url>"
      ]
    pair f s =
      let pt = baseUrl <> f PtBr s
          en = baseUrl <> f En s
       in entry pt pt en <> entry en pt en
    lines' =
      [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      , "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" xmlns:xhtml=\"http://www.w3.org/1999/xhtml\">"
      ]
        <> entry (baseUrl <> "/") (baseUrl <> "/") (baseUrl <> "/?lang=en")
        <> concatMap (pair Layout.path) (filter (not . Site.noIndex) Site.allSlugs)
        -- Pages the server renders. Study pages are not listed: they change at run time (ADR 0004).
        <> concatMap (pair Layout.dynamicPath) dynamicSlugs
        <> ["</urlset>"]

securityTxt :: Day -> Text
securityTxt today =
  "# How to report a vulnerability in marola: privately, on GitHub. There is no security e-mail.\n"
    <> "Contact: https://github.com/marola-dev/marola-site/security/advisories/new\n"
    <> "Expires: "
    <> T.pack (showGregorian (addDays expiresDays today))
    <> "T00:00:00Z\n"
    <> "Policy: "
    <> securityPolicy
    <> "\n"
    <> "Preferred-Languages: pt-BR, en\n"
    <> "Canonical: "
    <> baseUrl
    <> "/.well-known/security.txt\n"

-- | Each file with its path from the output folder.
files :: Env -> Day -> Either Text [(Text, Text)]
files env today = do
  members <- Members.parse (envMembers env)
  Right
    [ ("robots.txt", robots)
    , ("sitemap.xml", sitemap)
    , ("llms.txt", llms (envAreas env))
    , ("humans.txt", Members.humans members)
    , (".well-known/security.txt", securityTxt today)
    ]
