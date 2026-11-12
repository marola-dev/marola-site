-- | The cases of scripts/site_meta.py's self-test, plus the rules the build adds: both languages in the sitemap.
module MetaSpec (spec) where

import Data.Char (isAsciiLower)
import Data.List (sort)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Calendar (diffDays, fromGregorian)
import Marola.Pages.Language (allLanguages)
import qualified Marola.Pages.Language as Language
import qualified Marola.Pages.Layout as Layout
import qualified Marola.Pages.Meta as Meta
import Marola.Pages.Site (Area (..), Env (..))
import qualified Marola.Pages.Site as Site
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
            | rest <- occurrences "(https://marola.dev/" (Meta.llms areas)
            , let name = T.takeWhile (\c -> isAsciiLower c || c == '-') rest
            , not (T.null name)
            , ".html)" `T.isPrefixOf` T.drop (T.length name) rest
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
