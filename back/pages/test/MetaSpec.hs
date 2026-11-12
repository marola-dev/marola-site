-- | The cases of scripts/site_meta.py's self-test, plus the rules the build adds: both languages in the sitemap.
module MetaSpec (spec) where

import Data.Char (isAsciiLower)
import Data.List (sort)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (diffDays, fromGregorian)
import Marola.Pages.Language (allLanguages)
import Marola.Pages.Language qualified as Language
import Marola.Pages.Layout qualified as Layout
import Marola.Pages.Loader (readText)
import Marola.Pages.MapPage qualified as MapPage
import Marola.Pages.Meta qualified as Meta
import Marola.Pages.Site (Area (..), Env (..))
import Marola.Pages.Site qualified as Site
import Support
import Test.Hspec

base :: Text
base = "https://marola.dev"

sitemapLocs :: [Text]
sitemapLocs = betweenAll "<loc>" "</loc>" Meta.sitemap

spec :: Env -> Spec
spec env = describe "meta" $ do
  let areas = envAreas env
  it "llms.txt opens with the H1 and the blockquote" $
    Meta.llms areas `shouldSatisfy` T.isPrefixOf "# marola\n\n> "
  it "llms.txt lists every area in site/areas.json" $ do
    areas `shouldNotBe` []
    mapM_ (\a -> Meta.llms areas `shouldSatisfy` has (base <> "/data/" <> areaId a <> "/latest.json")) areas
  it "a new area appears with no edit" $
    Meta.llms (areas <> [Area "recife" "Recife"]) `shouldSatisfy` has (base <> "/data/recife/latest.json")
  it "llms.txt names every published page but the 404 and the thank-you page" $ do
    let listed =
          Set.fromList
            [ name
            | rest <- occurrences "(https://marola.dev/" (Meta.llms areas),
              let name = T.takeWhile (\c -> isAsciiLower c || c == '-') rest,
              not (T.null name),
              ".html)" `T.isPrefixOf` T.drop (T.length name) rest
            ]
        published = Set.fromList (filter (`notElem` ["404", "contact-sent"]) Site.allSlugs)
    listed `shouldBe` published
  it "llms.txt links the OpenAPI document and the agent guide, and the sitemap does not list them" $
    mapM_
      ( \url -> do
          Meta.llms areas `shouldSatisfy` has url
          Meta.sitemap `shouldNotSatisfy` has url
      )
      [base <> "/api/v1/openapi.json", base <> "/api/v1/skill.md"]
  it "the sitemap has every indexable page in both languages, the map once" $ do
    let indexable = filter (not . Site.noIndex) Site.allSlugs
    length sitemapLocs `shouldBe` 1 + 2 * (length indexable + length Meta.dynamicSlugs)
    all (T.isPrefixOf (base <> "/")) sitemapLocs `shouldBe` True
    mapM_ (\(s, l) -> sitemapLocs `shouldContain` [base <> Layout.path l s]) [(s, l) | s <- indexable, l <- allLanguages]
  it "no noindex page is in the sitemap, in either language" $
    mapM_
      (\(s, l) -> sitemapLocs `shouldNotContain` [base <> Layout.path l s])
      [(s, l) | s <- filter Site.noIndex Site.allSlugs, l <- allLanguages]
  it "each sitemap url names its alternates and x-default" $
    mapM_
      (\h -> count ("hreflang=\"" <> h <> "\"") Meta.sitemap `shouldBe` length sitemapLocs)
      [Language.tag minBound, Language.tag maxBound, "x-default"]
  it "every sitemap page is a file the build writes" $ do
    let written = either (error . T.unpack) (Set.fromList . map fst) (Site.allPages env)
    mapM_
      ( \loc -> do
          let p = T.drop (T.length base) loc
          if p /= "/" && not (any (\s -> ("/" <> s) `T.isSuffixOf` p) Meta.dynamicSlugs)
            then Set.member (T.dropWhile (== '/') p) written `shouldBe` True
            else pure ()
      )
      sitemapLocs
  it "Expires is under a year from the build" $ do
    Meta.securityTxt (fromGregorian 2026 11 11) `shouldSatisfy` has "Expires: 2027-11-10T00:00:00Z\n"
    diffDays (fromGregorian 2027 11 10) (fromGregorian 2026 11 11) `shouldSatisfy` (< 365)
  it "security.txt has the RFC 9116 fields" $
    mapM_
      (\f -> Meta.securityTxt (fromGregorian 2026 11 11) `shouldSatisfy` has ("\n" <> f <> ": "))
      ["Contact", "Policy", "Canonical"]
  it "the build writes the five metadata files" $
    fmap (sort . map fst) (Meta.files env (fromGregorian 2026 11 11))
      `shouldBe` Right [".well-known/security.txt", "humans.txt", "llms.txt", "robots.txt", "sitemap.xml"]
  it "robots.txt allows all and points at the sitemap" $ do
    Meta.robots `shouldSatisfy` has "User-agent: *\nAllow: /\n"
    Meta.robots `shouldSatisfy` has ("Sitemap: " <> base <> "/sitemap.xml")
  it "robots.txt keeps crawlers off the sign-in and the account pages, and nothing public" $ do
    mapM_ (\p -> Meta.robots `shouldSatisfy` has ("Disallow: " <> p <> "\n")) ["/auth/", "/account", "/en/account", "/report/", "/en/report/"]
    mapM_ (\p -> Meta.robots `shouldNotSatisfy` has ("Disallow: " <> p)) ["/studies", "/submit", "/api", "/data", "/en/\n", "/\n"]
  it "the English map page: lang, title, description, canonical and og tags, from front/index.html" $ do
    dir <- root
    page <- readText (dir <> "/front/index.html")
    case MapPage.english (envCatalog env) page of
      Left e -> expectationFailure (T.unpack e)
      Right en -> do
        en `shouldSatisfy` has "<html lang=\"en\">"
        en `shouldSatisfy` has "<link rel=\"canonical\" href=\"https://marola.dev/?lang=en\">"
        en `shouldSatisfy` has "<meta property=\"og:url\" content=\"https://marola.dev/?lang=en\">"
        en `shouldSatisfy` has "<meta property=\"og:locale\" content=\"en_US\">"
        en `shouldSatisfy` has MapPage.descriptionEn
        en `shouldNotSatisfy` has MapPage.descriptionPt
        en `shouldNotSatisfy` has "condições do mar"
        en `shouldSatisfy` has "<link rel=\"alternate\" hreflang=\"en\" href=\"https://marola.dev/?lang=en\">"
  it "the English map page fails the build when front/index.html drifts from it" $
    MapPage.english (envCatalog env) "<html lang=\"pt-BR\"><title>x</title>" `shouldSatisfy` either (const True) (const False)
