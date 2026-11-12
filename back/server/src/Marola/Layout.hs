-- | The frame of every page the server renders: head, nav, header, footer and the language switch.
-- The static pages' layout (back/pages, with the pieces of the nav and icons it draws), so a study page has
-- the same chrome as the static pages. The catalogs are the site's, read from @MAROLA_STATIC/i18n@.
module Marola.Layout
  ( Language (..),
    Catalog,
    Locale (..),
    PageHead (..),
    languageTag,
    loadCatalog,
    t,
    origin,
    path,
    dynamicPath,
    page,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson qualified as A
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Marola.Vdom
import System.FilePath ((</>))

data Language = PtBr | En deriving (Eq, Ord, Show)

languageTag :: Language -> Text
languageTag = \case
  PtBr -> "pt-BR"
  En -> "en"

type Catalog = Map Language (Map Text Text)

data Locale = Locale {catalog :: Catalog, language :: Language}

-- | Both catalogs, or the file that failed.
loadCatalog :: FilePath -> IO (Either String Catalog)
loadCatalog dir = do
  let one lang = do
        let file = dir </> (if lang == PtBr then "pt-BR" else "en") <> ".json"
        bytes <- try (BS.readFile file) :: IO (Either SomeException BS.ByteString)
        pure $ case bytes of
          Left e -> Left (file <> ": " <> show e)
          Right b -> either (Left . ((file <> ": ") <>)) (Right . (lang,)) (A.eitherDecodeStrict b)
  pt <- one PtBr
  en <- one En
  pure (Map.fromList <$> sequence [pt, en])

-- | The message for a key in the language, else the source language's (pt-BR), else the key. The
-- keys the chrome uses carry no ICU argument, so the text is used as it is.
t :: Locale -> Text -> Text
t loc key = case Map.lookup loc.language loc.catalog >>= Map.lookup key of
  Just m -> m
  Nothing -> maybe key id (Map.lookup PtBr loc.catalog >>= Map.lookup key)

data PageHead = PageHead
  { -- | The file name without @.html@.
    slug :: Text,
    title :: Text,
    description :: Text,
    noIndex :: Bool,
    -- | The canonical link, the language alternates and @og:url@.
    canonical :: Bool,
    -- | The slug of the nav link to mark as the current page.
    current :: Maybe Text,
    -- | A page the server renders: its address has no @.html@.
    dynamic :: Bool
  }

origin :: Text
origin = "https://marola.dev"

prefixOf :: Language -> Text
prefixOf = \case
  En -> "/en/"
  PtBr -> "/"

path :: Language -> Text -> Text
path lang s = prefixOf lang <> s <> ".html"

dynamicPath :: Language -> Text -> Text
dynamicPath lang s = prefixOf lang <> s

whereOf :: PageHead -> Language -> Text
whereOf p lang = if p.dynamic then dynamicPath lang p.slug else path lang p.slug

mapPath :: Language -> Text
mapPath = \case
  En -> "/?lang=en"
  PtBr -> "/"

ogLocale :: Language -> Text
ogLocale = \case
  En -> "en_US"
  PtBr -> "pt_BR"

meta :: [(Text, Text)] -> Node
meta as = el "meta" as []

link :: [(Text, Text)] -> Node
link as = el "link" as []

headNodes :: Language -> PageHead -> [Node]
headNodes lang p =
  let other = if lang == En then PtBr else En
      canon =
        if p.canonical
          then
            [ link [("rel", "canonical"), ("href", origin <> whereOf p lang)],
              link [("rel", "alternate"), ("hreflang", languageTag PtBr), ("href", origin <> whereOf p PtBr)],
              link [("rel", "alternate"), ("hreflang", languageTag En), ("href", origin <> whereOf p En)],
              link [("rel", "alternate"), ("hreflang", "x-default"), ("href", origin <> whereOf p PtBr)]
            ]
          else []
   in [ meta [("charset", "utf-8")],
        meta [("name", "viewport"), ("content", "width=device-width, initial-scale=1")],
        el "title" [] [text p.title],
        meta [("name", "description"), ("content", p.description)],
        meta [("name", "theme-color"), ("content", "#ffffff")]
      ]
        <> [meta [("name", "robots"), ("content", "noindex")] | p.noIndex]
        <> canon
        <> [ meta [("property", "og:type"), ("content", "website")],
             meta [("property", "og:site_name"), ("content", "marola")],
             meta [("property", "og:title"), ("content", p.title)],
             meta [("property", "og:description"), ("content", p.description)]
           ]
        <> [meta [("property", "og:url"), ("content", origin <> whereOf p lang)] | p.canonical]
        <> [ meta [("property", "og:locale"), ("content", ogLocale lang)],
             meta [("property", "og:locale:alternate"), ("content", ogLocale other)],
             meta [("name", "twitter:card"), ("content", "summary")],
             link [("rel", "icon"), ("href", "/favicon.svg"), ("type", "image/svg+xml")],
             link [("rel", "stylesheet"), ("href", "/style.css")]
           ]

-- | An inline decorative svg: hidden from assistive technology, not focusable (NavView.svg).
decorative :: [Attr] -> [Node] -> Node
decorative as = svg "svg" (attr "aria-hidden" "true" : attr "focusable" "false" : as)

langLink :: Locale -> PageHead -> Language -> Text -> Text -> Node
langLink loc p lang label nm =
  el
    "a"
    [ attr "href" (whereOf p lang),
      attr "lang" (languageTag lang),
      attr "hreflang" (languageTag lang),
      attr "aria-label" nm,
      attr "aria-current" (if loc.language == lang then "true" else "false")
    ]
    [text label]

languageSwitch :: Locale -> PageHead -> Node
languageSwitch loc p =
  el
    "div"
    [cls "lang", attr "role" "group", attr "aria-label" (t loc "lang.label")]
    [ decorative
        [cls "lang-icon", attr "viewBox" "0 0 16 16"]
        [ svg "circle" [attr "cx" "8", attr "cy" "8", attr "r" "6.5"] [],
          svg "ellipse" [attr "cx" "8", attr "cy" "8", attr "rx" "2.8", attr "ry" "6.5"] [],
          svg "path" [attr "d" "M1.5 8h13"] []
        ],
      langLink loc p PtBr "PT-BR" "português (Brasil)",
      langLink loc p En "EN" "English"
    ]

linkedin :: Locale -> Node
linkedin loc =
  el
    "a"
    [ cls "li",
      attr "href" "https://www.linkedin.com/company/marola-dev/",
      attr "target" "_blank",
      attr "rel" "noopener",
      attr "aria-label" (t loc "li.label"),
      attr "title" (t loc "li.label")
    ]
    [ decorative
        [cls "li-mark", attr "viewBox" "0 0 24 24"]
        [ svg "path" [attr "d" "M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-4 0v7h-4v-7a6 6 0 0 1 6-6z"] [],
          svg "rect" [attr "x" "2", attr "y" "9", attr "width" "4", attr "height" "12"] [],
          svg "circle" [attr "cx" "4", attr "cy" "4", attr "r" "2"] []
        ],
      el "span" [cls "li-name"] [text (t loc "li.name")]
    ]

githubMark :: Text
githubMark =
  "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.06-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"

github :: Locale -> Node
github loc =
  el
    "a"
    [ cls "gh",
      attr "href" "https://github.com/marola-dev/marola",
      attr "aria-label" (t loc "gh.label"),
      attr "title" (t loc "gh.title")
    ]
    [ decorative [cls "gh-mark", attr "viewBox" "0 0 16 16"] [svg "path" [attr "fill" "currentColor", attr "d" githubMark] []],
      el "span" [cls "gh-name"] [el "span" [cls "gh-owner"] [text "marola-dev/"], text "marola"],
      el
        "span"
        [cls "gh-star"]
        [ decorative
            [attr "viewBox" "0 0 16 16"]
            [svg "path" [attr "d" "M8 1.6l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.4l-3.8 2 .7-4.3-3.1-3 4.3-.6z"] []],
          el "span" [] [text (t loc "gh.star")]
        ]
    ]

-- | Icons.icon "brand".
brand :: Node
brand =
  svg
    "svg"
    [cls "ic ic-brand", attr "viewBox" "0 0 24 24", attr "aria-hidden" "true", attr "focusable" "false"]
    [ svg "path" [attr "d" "M2 9c2.5 0 2.5-2.5 5-2.5S9.5 9 12 9s2.5-2.5 5-2.5S19.5 9 22 9"] [],
      svg "path" [attr "d" "M2 16c2.5 0 2.5-2.5 5-2.5s2.5 2.5 5 2.5 2.5-2.5 5-2.5 2.5 2.5 5 2.5"] []
    ]

navLink :: Locale -> PageHead -> Text -> Text -> Node
navLink loc p s key =
  el "a" ([attr "href" (path loc.language s)] <> [attr "aria-current" "page" | p.current == Just s]) [text (t loc key)]

external :: Locale -> Text -> Text -> Node
external loc url key = el "a" [attr "href" url] [text (t loc key)]

nav :: Locale -> PageHead -> Node
nav loc p =
  el
    "nav"
    [cls "sitenav", attr "aria-label" (t loc "nav.label")]
    [ external loc "https://docs.marola.dev/" "nav.docs",
      el
        "span"
        [attr "aria-disabled" "true"]
        [el "span" [] [text (t loc "nav.alerts")], text " ", el "i" [] [text (t loc "nav.soon")]],
      navLink loc p "news" "nav.news",
      el
        "a"
        ([attr "href" (dynamicPath loc.language "studies")] <> [attr "aria-current" "page" | p.current == Just "studies"])
        [text (t loc "nav.studies")],
      navLink loc p "about" "nav.about",
      navLink loc p "contact" "nav.contact",
      external loc "https://github.com/marola-dev/marola-research/blob/main/README.md" "nav.research",
      external loc "https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf" "nav.contribute",
      navLink loc p "members" "nav.members",
      navLink loc p "support" "nav.donate",
      languageSwitch loc p,
      linkedin loc,
      github loc
    ]

header :: Locale -> Node
header loc =
  el
    "header"
    [cls "bar"]
    [ el "div" [cls "brand"] [el "h1" [] [brand, text "marola"], el "p" [cls "tagline"] [text (t loc "header.tagline")]],
      el "div" [cls "controls"] [el "a" [attr "href" (mapPath loc.language)] [text (t loc "about.back")]]
    ]

-- | The whole document for the children of @<main class="main about">@.
page :: Locale -> PageHead -> [Node] -> Text
page loc hd mainNodes =
  let lang = loc.language
      html =
        el
          "html"
          [attr "lang" (languageTag lang)]
          [ el "head" [] (headNodes lang hd),
            el
              "body"
              []
              [ nav loc hd,
                header loc,
                el "main" [cls "main about"] mainNodes,
                el
                  "footer"
                  [cls "footer"]
                  [ el "p" [] [text (t loc "footer.privacy")],
                    el
                      "p"
                      []
                      [ el "a" [attr "href" (dynamicPath lang "submit")] [text (t loc "footer.submit")],
                        text " · ",
                        el "a" [attr "href" (path lang "privacy")] [text (t loc "footer.privacy_page")],
                        text " · ",
                        el "a" [attr "href" (path lang "takedown")] [text (t loc "footer.takedown")]
                      ]
                  ]
              ]
          ]
   in "<!doctype html>\n" <> toHtml html <> "\n"
