module PageSpec (spec) where

import Data.Char (isAsciiLower, toLower)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Pages.Language (Language (..), allLanguages)
import Marola.Pages.Language qualified as Language
import Marola.Pages.Layout qualified as Layout
import Marola.Pages.Meta qualified as Meta
import Marola.Pages.Site (Env (..))
import Marola.Pages.Site qualified as Site
import Support
import Test.Hspec

cases :: [(Text, Language)]
cases = [(s, l) | s <- Site.allSlugs, l <- allLanguages]

allHrefs :: Text -> [Text]
allHrefs = betweenAll "href=\"" "\""

-- @<script|<style| style=| on[a-z]+=@, ignoring case.
scripted :: Text -> Bool
scripted html =
  let low = T.map toLower html
      handler r = let n = T.takeWhile isAsciiLower r in not (T.null n) && "=" `T.isPrefixOf` T.drop (T.length n) r
   in any (`T.isInfixOf` low) ["<script", "<style", " style="] || any handler (occurrences " on" low)

forEach :: Env -> String -> (Text -> Language -> Text -> Expectation) -> Spec
forEach env what check = it what (mapM_ (\(s, l) -> check s l (renderWith env s l)) cases)

spec :: Env -> Spec
spec env = describe "pages" $ do
  forEach env "the document has its language, a favicon and the shared style" $ \_ l html -> do
    html `shouldSatisfy` T.isPrefixOf ("<!doctype html>\n<html lang=\"" <> Language.tag l <> "\">")
    html `shouldSatisfy` has "<link rel=\"icon\" href=\"/favicon.png\" type=\"image/png\">"
    html `shouldSatisfy` has "<link rel=\"apple-touch-icon\" href=\"/apple-touch-icon.png\">"
    html `shouldSatisfy` has "<link rel=\"stylesheet\" href=\"/style.css\">"
  forEach env "canonical and the three alternates point at the page's own files" $ \s l html ->
    if s == "404"
      then html `shouldNotSatisfy` has "rel=\"canonical\""
      else do
        html `shouldSatisfy` has ("<link rel=\"canonical\" href=\"" <> Layout.origin <> Layout.path l s <> "\">")
        html `shouldSatisfy` has ("hreflang=\"pt-BR\" href=\"" <> Layout.origin <> Layout.path PtBr s <> "\"")
        html `shouldSatisfy` has ("hreflang=\"en\" href=\"" <> Layout.origin <> Layout.path En s <> "\"")
        html `shouldSatisfy` has ("hreflang=\"x-default\" href=\"" <> Layout.origin <> Layout.path PtBr s <> "\"")
  forEach env "no script, no style element, no style attribute, no handler" $ \_ _ html ->
    scripted html `shouldBe` False
  forEach env "the language switch is two plain links to this page in each language" $ \s _ html -> do
    html `shouldSatisfy` has ("<a href=\"" <> Layout.path PtBr s <> "\" lang=\"pt-BR\"")
    html `shouldSatisfy` has ("<a href=\"" <> Layout.path En s <> "\" lang=\"en\"")
  forEach env "the nav links go to the page's own language" $ \_ l html ->
    mapM_ (\n -> allHrefs html `shouldContain` [Layout.path l n]) Layout.navSlugs
  forEach env "the nav links the studies list and the footer the submit page, in the page's language" $ \_ l html -> do
    allHrefs html `shouldContain` [Layout.dynamicPath l "studies"]
    allHrefs html `shouldContain` [Layout.dynamicPath l "submit"]
  forEach env "the footer links the privacy and takedown pages, in the page's language" $ \_ l html -> do
    allHrefs html `shouldContain` [Layout.path l "privacy"]
    allHrefs html `shouldContain` [Layout.path l "takedown"]
  forEach env "the chrome is the map page's: the top bar, the wordmark as a link to the map, the eye, the credit line" $ \s l html -> do
    html `shouldSatisfy` has "<body><header class=\"top\"><div class=\"brand\"><h1><a href=\""
    html `shouldSatisfy` has ("<a href=\"" <> Layout.mapPath l <> "\"><span class=\"logo\" aria-hidden=\"true\"></span>marola</a></h1>")
    html `shouldSatisfy` has "<a class=\"piabrota\" href=\"https://piabrota.art\" target=\"_blank\" rel=\"noopener\""
    html `shouldSatisfy` has "<div class=\"navtools\"><div class=\"lang\" role=\"group\""
    html `shouldSatisfy` has ("<div class=\"bar pagebar\"><div class=\"controls\"><a href=\"" <> Layout.mapPath l <> "\">")
    html `shouldSatisfy` has ("<main class=\"main about p-" <> s <> "\">")
    html `shouldSatisfy` has "<meta name=\"theme-color\" content=\"#0B0D12\">"
    html `shouldSatisfy` (not . has "<a href=\"https://github.com/h0ffmann\" target=")
    html `shouldSatisfy` has ("<a href=\"" <> Layout.path l "members" <> "\">")
    html `shouldSatisfy` has "piabrota</a></p></footer></body>"
    count "<h1" html `shouldBe` 1
  it "a page of a nav section has its eyebrow; the 404 has none" $ do
    renderWith env "about" PtBr `shouldSatisfy` has "<p class=\"eyebrow\">marola · sobre</p><article"
    renderWith env "contact-sent" En `shouldSatisfy` has "<p class=\"eyebrow\">marola · contact</p>"
    renderWith env "404" En `shouldNotSatisfy` has "class=\"eyebrow\""
  it "the privacy and takedown pages are in the build and the sitemap, in both languages, and say what they must" $ do
    mapM_
      ( \s -> do
          Site.allSlugs `shouldContain` [s]
          Site.noIndex s `shouldBe` False
          mapM_ (\l -> Meta.sitemap `shouldSatisfy` has (Layout.origin <> Layout.path l s)) allLanguages
      )
      ["privacy", "takedown"]
    let en = renderWith env "privacy" En
        pt = renderWith env "privacy" PtBr
    mapM_ (\n -> en `shouldSatisfy` has n) ["not legal advice", "IP address", "tombstone", "/account"]
    mapM_ (\n -> pt `shouldSatisfy` has n) ["aconselhamento jurídico", "endereço IP", "lápide", "/account"]
  it "every nav link has a page in the build" $
    mapM_ (\s -> Site.allSlugs `shouldContain` [s]) Layout.navSlugs
  it "only the contact pages and the 404 stay out of search results" $
    mapM_
      ( \(s, l) ->
          has "<meta name=\"robots\" content=\"noindex\">" (renderWith env s l)
            `shouldBe` (s `elem` ["contact", "contact-sent", "404"])
      )
      cases
  it "the contact form posts to the language's own path, with a honeypot and a required email" $
    mapM_
      ( \(l, action) -> do
          let html = renderWith env "contact" l
          html `shouldSatisfy` has ("<form class=\"contact\" action=\"" <> action <> "\" method=\"POST\">")
          html `shouldSatisfy` has "name=\"website\" tabindex=\"-1\" autocomplete=\"off\" aria-hidden=\"true\" hidden=\"\""
          html `shouldSatisfy` has "<input type=\"email\" name=\"email\" required=\"\" autocomplete=\"email\">"
          html `shouldSatisfy` has "<textarea name=\"message\" rows=\"6\" required=\"\"></textarea>"
      )
      [(PtBr, "/contact"), (En, "/en/contact")]
  it "the other pages have no form" $
    mapM_ (\(s, l) -> if s /= "contact" then renderWith env s l `shouldNotSatisfy` has "<form" else pure ()) cases
  it "about keeps its credits and the map's sources, in both languages" $
    mapM_
      ( \l ->
          mapM_
            (\n -> renderWith env "about" l `shouldSatisfy` has n)
            [ "Carlos Toledo",
              "https://github.com/carlostoledo1891",
              "https://swell-floripa.vercel.app/",
              "Luftrum",
              "Porrumentzio",
              "https://creativecommons.org/licenses/by/3.0/",
              "https://github.com/marola-dev/marola/discussions/676",
              "https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf"
            ]
      )
      allLanguages
  it "support links Patreon and keeps the coming-soon channel disabled" $
    mapM_
      ( \l -> do
          let html = renderWith env "support" l
          html `shouldSatisfy` has "href=\"https://www.patreon.com/maroladev\""
          html `shouldSatisfy` has "<span aria-disabled=\"true\">Buy Me a Coffee <i>"
      )
      allLanguages
  it "a missing catalog key shows the key" $ do
    let bare = env {envCatalog = Map.fromList [(PtBr, Map.empty), (En, Map.empty)]}
    renderWith bare "about" En `shouldSatisfy` has ">nav.about</a>"
  it "the build lists pt-BR at the root and English under en/" $
    fmap (sort . map fst) (Site.allPages env)
      `shouldBe` Right
        [ "404.html",
          "about.html",
          "contact-sent.html",
          "contact.html",
          "en/404.html",
          "en/about.html",
          "en/contact-sent.html",
          "en/contact.html",
          "en/members.html",
          "en/news.html",
          "en/privacy.html",
          "en/support.html",
          "en/takedown.html",
          "members.html",
          "news.html",
          "privacy.html",
          "support.html",
          "takedown.html"
        ]
