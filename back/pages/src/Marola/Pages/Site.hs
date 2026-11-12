-- | The pages: one page is a function from a language to its HTML text.
module Marola.Pages.Site
  ( Area (..),
    Env (..),
    slugs,
    allSlugs,
    noIndex,
    contentKey,
    file,
    render,
    allPages,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Pages.Html (Node)
import Marola.Pages.Html qualified as H
import Marola.Pages.I18n (Catalog, Locale (..))
import Marola.Pages.I18n qualified as I18n
import Marola.Pages.Language (Language (..))
import Marola.Pages.Language qualified as Language
import Marola.Pages.Layout qualified as Layout
import Marola.Pages.Markdown (Doc, collect)
import Marola.Pages.Markdown qualified as Markdown
import Marola.Pages.Members qualified as Members
import Marola.Pages.News qualified as News

-- | An area of @site/areas.json@: llms.txt reads its id and name.
data Area = Area {areaId :: Text, areaName :: Text}
  deriving (Eq, Show)

-- | What the pages are made of, as read from disk.
data Env = Env
  { envCatalog :: Catalog,
    -- | @<slug>.<language tag>@ to the file's text.
    envContent :: Map Text Text,
    -- | The news posts: file name and text, without README.md.
    envNews :: [(Text, Text)],
    -- | @site/content/news/README.md@, whose index must list every post.
    envNewsIndex :: Text,
    -- | MEMBERS.md of marola-dev/.github.
    envMembers :: Text,
    -- | The avatar files of @site/static/img/members/@: the GitHub login to its file name.
    envAvatars :: Map Text Text,
    envAreas :: [Area]
  }

-- | Pages whose body is Markdown, by file name without @.html@.
slugs :: [Text]
slugs = ["about", "support", "contact", "contact-sent", "privacy", "takedown", "404"]

-- | Every page of the site, in the order of the nav.
allSlugs :: [Text]
allSlugs = ["news", "about", "contact", "members", "support", "privacy", "takedown", "contact-sent", "404"]

-- | A page a search engine must not list.
noIndex :: Text -> Bool
noIndex s = s `elem` ["contact", "contact-sent", "404"]

contentKey :: Text -> Language -> Text
contentKey s l = s <> "." <> Language.tag l

-- | Where a page is written, from the output folder: pt-BR at the root, English under @en/@.
file :: Language -> Text -> Text
file l s = T.dropWhile (== '/') (Layout.path l s)

-- The form posts to the same path the page is under, so the server can answer in the visitor's language.
form :: Locale -> Node
form loc =
  H.el
    "div"
    [H.cls "about-body"]
    [ H.el
        "form"
        [ H.cls "contact",
          H.attr "action" (if language loc == En then "/en/contact" else "/contact"),
          H.attr "method" "POST"
        ]
        [ -- The honeypot: a person never sees it, the server drops a post that fills it.
          H.el
            "input"
            ( [ H.attr "type" "text",
                H.attr "name" "website",
                H.attr "tabindex" "-1",
                H.attr "autocomplete" "off",
                H.attr "aria-hidden" "true"
              ]
                <> H.hidden True
            )
            [],
          field "contact.name" $
            H.el "input" [H.attr "type" "text", H.attr "name" "name", H.attr "required" "", H.attr "autocomplete" "name"] [],
          field "contact.email" $
            H.el "input" [H.attr "type" "email", H.attr "name" "email", H.attr "required" "", H.attr "autocomplete" "email"] [],
          field "contact.message" $
            H.el "textarea" [H.attr "name" "message", H.attr "rows" "6", H.attr "required" ""] [],
          H.el "button" [H.attr "type" "submit"] [H.text (I18n.t loc "contact.send")]
        ]
    ]
  where
    field key control = H.el "label" [] [H.el "span" [] [H.text (I18n.t loc key)], H.text " ", control]

-- How each page differs from plain prose: its nav mark, whether a search engine may list it.
headOf :: Text -> Doc -> Layout.PageHead
headOf s doc =
  Layout.PageHead
    { Layout.slug = s,
      Layout.title = Markdown.title doc,
      Layout.description = Markdown.description doc,
      Layout.noIndex = noIndex s,
      Layout.canonical = s /= "404",
      Layout.dynamic = False,
      Layout.current = case s of
        "contact" -> Just "contact"
        "contact-sent" -> Just "contact"
        "404" -> Nothing
        other -> Just other
    }

-- | One page in one language, or why it cannot be made.
render :: Env -> Text -> Language -> Either Text Text
render env s l =
  case Map.lookup (contentKey s l) (envContent env) of
    Nothing -> Left ("no content for " <> contentKey s l)
    Just txt -> do
      doc <- either (\e -> Left (contentKey s l <> ": " <> e)) Right (Markdown.parse txt)
      let page main' = Right (Layout.page loc (headOf s doc) main')
          article = H.el "article" [H.cls "about-body", H.attr "lang" (Language.tag l)] (Markdown.body doc)
      case s of
        "news" -> do
          posts <- News.build (envNews env) (envNewsIndex env)
          page (map News.article (News.forLanguage l posts))
        "members" -> do
          members <- Members.parse (envMembers env)
          Members.checkAvatars (envAvatars env) members
          page [Members.article l (envAvatars env) members]
        "contact" -> page [article, form loc]
        _ -> page [article]
  where
    loc = Locale (envCatalog env) l

-- | Every page in every language: the path from the output folder and the text to write there.
allPages :: Env -> Either Text [(Text, Text)]
allPages env = collect [(file l s,) <$> render env s l | s <- allSlugs, l <- Language.allLanguages]
