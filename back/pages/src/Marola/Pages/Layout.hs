-- | The frame of every static page: head, nav, header, footer and the language switch. The same
-- chrome as the map page, with plain links where the map page has buttons, and no script, with the parts
-- of the map page's nav and icons it draws.
module Marola.Pages.Layout
  ( PageHead (..),
    origin,
    path,
    dynamicPath,
    mapPath,
    navSlugs,
    page,
  )
where

import Data.Text (Text)
import Marola.Pages.Html (Attr, Node)
import Marola.Pages.Html qualified as H
import Marola.Pages.I18n (Locale (..))
import Marola.Pages.I18n qualified as I18n
import Marola.Pages.Language (Language (..))
import Marola.Pages.Language qualified as Language

data PageHead = PageHead
  { -- | The file name without @.html@: @about@, @contact-sent@.
    slug :: Text,
    title :: Text,
    description :: Text,
    noIndex :: Bool,
    -- | The canonical link, the language alternates and @og:url@. A 404 page answers any address,
    -- so it has none.
    canonical :: Bool,
    -- | The slug of the nav link to mark as the current page.
    current :: Maybe Text,
    -- | A page the server renders at run time: its address has no @.html@.
    dynamic :: Bool
  }

origin :: Text
origin = "https://marola.dev"

prefix :: Language -> Text
prefix En = "/en/"
prefix PtBr = "/"

-- | The path of a page: pt-BR at the root, English under @/en/@.
path :: Language -> Text -> Text
path l s = prefix l <> s <> ".html"

-- | The address of a page the server renders: no extension.
dynamicPath :: Language -> Text -> Text
dynamicPath l s = prefix l <> s

whereOf :: PageHead -> Language -> Text
whereOf p l = if dynamic p then dynamicPath l (slug p) else path l (slug p)

mapPath :: Language -> Text
mapPath En = "/?lang=en"
mapPath PtBr = "/"

ogLocale :: Language -> Text
ogLocale En = "en_US"
ogLocale PtBr = "pt_BR"

attrs :: [(Text, Text)] -> [Attr]
attrs = map (uncurry H.attr)

meta :: [(Text, Text)] -> Node
meta as = H.el "meta" (attrs as) []

link :: [(Text, Text)] -> Node
link as = H.el "link" (attrs as) []

headNodes :: Language -> PageHead -> [Node]
headNodes l p =
  [ meta [("charset", "utf-8")],
    meta [("name", "viewport"), ("content", "width=device-width, initial-scale=1")],
    H.el "title" [] [H.text (title p)],
    meta [("name", "description"), ("content", description p)],
    meta [("name", "theme-color"), ("content", "#ffffff")]
  ]
    <> [meta [("name", "robots"), ("content", "noindex")] | noIndex p]
    <> ( if canonical p
           then
             [ link [("rel", "canonical"), ("href", origin <> whereOf p l)],
               link [("rel", "alternate"), ("hreflang", Language.tag PtBr), ("href", origin <> whereOf p PtBr)],
               link [("rel", "alternate"), ("hreflang", Language.tag En), ("href", origin <> whereOf p En)],
               link [("rel", "alternate"), ("hreflang", "x-default"), ("href", origin <> whereOf p PtBr)]
             ]
           else []
       )
    <> [ meta [("property", "og:type"), ("content", "website")],
         meta [("property", "og:site_name"), ("content", "marola")],
         meta [("property", "og:title"), ("content", title p)],
         meta [("property", "og:description"), ("content", description p)]
       ]
    <> [meta [("property", "og:url"), ("content", origin <> whereOf p l)] | canonical p]
    <> [ meta [("property", "og:locale"), ("content", ogLocale l)],
         meta [("property", "og:locale:alternate"), ("content", ogLocale other)],
         meta [("name", "twitter:card"), ("content", "summary")],
         link [("rel", "icon"), ("href", "/favicon.svg"), ("type", "image/svg+xml")],
         link [("rel", "stylesheet"), ("href", "/style.css")]
       ]
  where
    other = if l == En then PtBr else En

-- | An inline decorative svg: hidden from assistive technology, not focusable (NavView.svg).
decorative :: [Attr] -> [Node] -> Node
decorative as = H.svg "svg" (H.attr "aria-hidden" "true" : H.attr "focusable" "false" : as)

svgEl :: Text -> [(Text, Text)] -> Node
svgEl t as = H.svg t (attrs as) []

langLink :: Locale -> PageHead -> Language -> Text -> Text -> Node
langLink loc p l label name =
  H.el
    "a"
    [ H.attr "href" (whereOf p l),
      H.attr "lang" (Language.tag l),
      H.attr "hreflang" (Language.tag l),
      H.attr "aria-label" name,
      H.attr "aria-current" (if language loc == l then "true" else "false")
    ]
    [H.text label]

languageSwitch :: Locale -> PageHead -> Node
languageSwitch loc p =
  H.el
    "div"
    [H.cls "lang", H.attr "role" "group", H.attr "aria-label" (I18n.t loc "lang.label")]
    [ decorative
        [H.cls "lang-icon", H.attr "viewBox" "0 0 16 16"]
        [ svgEl "circle" [("cx", "8"), ("cy", "8"), ("r", "6.5")],
          svgEl "ellipse" [("cx", "8"), ("cy", "8"), ("rx", "2.8"), ("ry", "6.5")],
          svgEl "path" [("d", "M1.5 8h13")]
        ],
      langLink loc p PtBr "PT-BR" "português (Brasil)",
      langLink loc p En "EN" "English"
    ]

linkedin :: Locale -> Node
linkedin loc =
  H.el
    "a"
    [ H.cls "li",
      H.attr "href" "https://www.linkedin.com/company/marola-dev/",
      H.attr "target" "_blank",
      H.attr "rel" "noopener",
      H.attr "aria-label" (I18n.t loc "li.label"),
      H.attr "title" (I18n.t loc "li.label")
    ]
    [ decorative
        [H.cls "li-mark", H.attr "viewBox" "0 0 24 24"]
        [ svgEl "path" [("d", "M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-4 0v7h-4v-7a6 6 0 0 1 6-6z")],
          svgEl "rect" [("x", "2"), ("y", "9"), ("width", "4"), ("height", "12")],
          svgEl "circle" [("cx", "4"), ("cy", "4"), ("r", "2")]
        ],
      H.el "span" [H.cls "li-name"] [H.text (I18n.t loc "li.name")]
    ]

githubMark :: Text
githubMark =
  "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.06-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"

github :: Locale -> Node
github loc =
  H.el
    "a"
    [ H.cls "gh",
      H.attr "href" "https://github.com/marola-dev/marola",
      H.attr "aria-label" (I18n.t loc "gh.label"),
      H.attr "title" (I18n.t loc "gh.title")
    ]
    [ decorative
        [H.cls "gh-mark", H.attr "viewBox" "0 0 16 16"]
        [svgEl "path" [("fill", "currentColor"), ("d", githubMark)]],
      H.el
        "span"
        [H.cls "gh-name"]
        [H.el "span" [H.cls "gh-owner"] [H.text "marola-dev/"], H.text "marola"],
      H.el
        "span"
        [H.cls "gh-star"]
        [ decorative
            [H.attr "viewBox" "0 0 16 16"]
            [svgEl "path" [("d", "M8 1.6l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.4l-3.8 2 .7-4.3-3.1-3 4.3-.6z")]],
          H.el "span" [] [H.text (I18n.t loc "gh.star")]
        ]
    ]

-- | Icons.icon "brand".
brand :: Node
brand =
  H.svg
    "svg"
    [ H.cls "ic ic-brand",
      H.attr "viewBox" "0 0 24 24",
      H.attr "aria-hidden" "true",
      H.attr "focusable" "false"
    ]
    [ svgEl "path" [("d", "M2 9c2.5 0 2.5-2.5 5-2.5S9.5 9 12 9s2.5-2.5 5-2.5S19.5 9 22 9")],
      svgEl "path" [("d", "M2 16c2.5 0 2.5-2.5 5-2.5s2.5 2.5 5 2.5 2.5-2.5 5-2.5 2.5 2.5 5 2.5")]
    ]

-- | The slugs the nav links to, in the order of the map page's nav.
navSlugs :: [Text]
navSlugs = ["news", "about", "contact", "members", "support"]

currentMark :: PageHead -> Text -> [Attr]
currentMark p s = [H.attr "aria-current" "page" | current p == Just s]

navLink :: Locale -> PageHead -> Text -> Text -> Node
navLink loc p s key =
  H.el "a" (H.attr "href" (path (language loc) s) : currentMark p s) [H.text (I18n.t loc key)]

external :: Locale -> Text -> Text -> Node
external loc url key = H.el "a" [H.attr "href" url] [H.text (I18n.t loc key)]

nav :: Locale -> PageHead -> Node
nav loc p =
  H.el
    "nav"
    [H.cls "sitenav", H.attr "aria-label" (I18n.t loc "nav.label")]
    [ external loc "https://docs.marola.dev/" "nav.docs",
      H.el
        "span"
        [H.attr "aria-disabled" "true"]
        [ H.el "span" [] [H.text (I18n.t loc "nav.alerts")],
          H.text " ",
          H.el "i" [] [H.text (I18n.t loc "nav.soon")]
        ],
      navLink loc p "news" "nav.news",
      H.el
        "a"
        (H.attr "href" (dynamicPath (language loc) "studies") : currentMark p "studies")
        [H.text (I18n.t loc "nav.studies")],
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
  H.el
    "header"
    [H.cls "bar"]
    [ H.el
        "div"
        [H.cls "brand"]
        [ H.el "h1" [] [brand, H.text "marola"],
          H.el "p" [H.cls "tagline"] [H.text (I18n.t loc "header.tagline")]
        ],
      H.el
        "div"
        [H.cls "controls"]
        [H.el "a" [H.attr "href" (mapPath (language loc))] [H.text (I18n.t loc "about.back")]]
    ]

-- | The whole document for the children of @<main class="main about">@.
page :: Locale -> PageHead -> [Node] -> Text
page loc p main' =
  "<!doctype html>\n" <> H.toHtml html <> "\n"
  where
    l = language loc
    html =
      H.el
        "html"
        [H.attr "lang" (Language.tag l)]
        [ H.el "head" [] (headNodes l p),
          H.el
            "body"
            []
            [ nav loc p,
              header loc,
              H.el "main" [H.cls "main about"] main',
              H.el
                "footer"
                [H.cls "footer"]
                [ H.el "p" [] [H.text (I18n.t loc "footer.privacy_ofm")],
                  H.el
                    "p"
                    []
                    [ H.el "a" [H.attr "href" (dynamicPath l "submit")] [H.text (I18n.t loc "footer.submit")],
                      H.text " · ",
                      H.el "a" [H.attr "href" (path l "privacy")] [H.text (I18n.t loc "footer.privacy_page")],
                      H.text " · ",
                      H.el "a" [H.attr "href" (path l "takedown")] [H.text (I18n.t loc "footer.takedown")]
                    ]
                ]
            ]
        ]
