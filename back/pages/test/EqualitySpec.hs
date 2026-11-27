-- | The pages against the old static pages that scripts/news_build.py and scripts/members_build.py
-- wrote into site/static: the same posts in the same order, the same people in the same order.
module EqualitySpec (spec) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Pages.Language (Language (..), allLanguages)
import Marola.Pages.Language qualified as Language
import Marola.Pages.Members qualified as Members
import Marola.Pages.Meta qualified as Meta
import Marola.Pages.Site (Env (..))
import Support
import Test.Hspec

articles :: Language -> Text -> [Text]
articles l = betweenAll ("<article class=\"about-body\" lang=\"" <> Language.tag l <> "\">") "</article>"

firstH2 :: Text -> Text
firstH2 a = visible (fromMaybe "" (between "<h2>" "</h2>" a))

names :: Text -> [Text]
names html = [htmlDecode (T.takeWhile (/= '<') r) | r <- occurrences "<span class=\"member-name\">" html]

spec :: Env -> Spec
spec env = describe "equality with the old static pages" $ do
  -- The legacy page is two languages until the cutover (scripts/news_build.py), so its parity
  -- covers the languages it has; ja and zh-Hant are new-site languages.
  let legacy = [PtBr, En]
  it "news: the same posts, in the same order, in each language" $ do
    old <- oldPage "news.html"
    mapM_
      ( \l -> do
          let o = articles l old
          o `shouldNotBe` []
          map firstH2 (articles l (renderWith env "news" l)) `shouldBe` map firstH2 o
      )
      legacy
  it "news: the same words, reading time and links in each post" $ do
    old <- oldPage "news.html"
    mapM_
      ( \l -> do
          let o = articles l old
              n = articles l (renderWith env "news" l)
          length n `shouldBe` length o
          mapM_ (\(a, b) -> (visible b, hrefs b) `shouldBe` (visible a, hrefs a)) (zip o n)
      )
      legacy
  it "members: the same people, in the same order, the same count, in each language" $ do
    old <- oldPage "members.html"
    mapM_
      ( \l -> do
          let o = names (head (articles l old))
          o `shouldNotBe` []
          names (head (articles l (renderWith env "members" l))) `shouldBe` o
      )
      legacy
  it "members: the same cards, after the short index, per language, and local avatars only" $ do
    old <- oldPage "members.html"
    mapM_
      ( \l -> do
          let o = head (articles l old)
              pg = renderWith env "members" l
              n = head (articles l pg)
              -- The short index of names is new-site only; the cards below it are the old page's.
              short = fromMaybe "" (between "<nav " "</nav>" n)
              cards = T.replace short "" n
              srcs = attrValues "img" "src" pg
          visible cards `shouldBe` visible o
          hrefs cards `shouldBe` hrefs o
          srcs `shouldNotBe` []
          all (T.isPrefixOf "/img/members/") srcs `shouldBe` True
          cards `shouldSatisfy` T.isInfixOf "id=\"member-"
      )
      legacy
  it "humans.txt: the same team as the old file" $ do
    old <- oldPage "humans.txt"
    let team s = fst (T.breakOn "/* SITE */" (snd (T.breakOn "Name: " s)))
    fmap (team . Members.humans) (Members.parse (envMembers env)) `shouldBe` Right (team old)
  it "robots.txt: the old file plus the Disallow block for the server's sign-in and account pages" $ do
    old <- oldPage "robots.txt"
    let serverOnly l = "Disallow:" `T.isPrefixOf` l || "# The sign-in redirect" `T.isPrefixOf` l
        legacy = T.unlines (filter (not . serverOnly) (T.lines Meta.robots))
    legacy `shouldBe` old
