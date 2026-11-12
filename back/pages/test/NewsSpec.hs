-- | The cases of scripts/news_build.py's self-test, one for one, plus the page built from the real posts.
module NewsSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Text (Text)
import qualified Data.Text as T
import Marola.Pages.Html (toHtml)
import Marola.Pages.Language (Language (..), allLanguages)
import qualified Marola.Pages.News as News
import Marola.Pages.Site (Env)
import Support
import Test.Hspec

pt, en, card :: Text
pt = "# olá\n\n2026-10-07\n\num lede.\n\n## seção\n\n- um [link](https://x.org/?a=1&b=2)\n- **dois**\n"
en = "# hello\n\n2026-10-07\n\nA lede.\n\n### sub\n\nText with `code`.\n"
card = "::: release v0.2.1 2026-10-08\n- a [change](https://x.org/1)\n[notes](https://x.org/n) · DOI"

good :: [(Text, Text)]
good = [("2026-10-07-a.pt-BR.md", pt), ("2026-10-07-a.en.md", en)]

articles :: Language -> [(Text, Text)] -> Text -> Either Text Text
articles l files index =
  T.intercalate "\n" . map (toHtml . News.article) . News.forLanguage l <$> News.build files index

ok :: Language -> [(Text, Text)] -> Text -> Text
ok l files index = either (error . T.unpack) id (articles l files index)

fails :: String -> [(Text, Text)] -> Text -> Spec
fails label files index = it label $ do
  isLeft (articles PtBr files index) `shouldBe` True
  isLeft (articles En files index) `shouldBe` True

replaceEn :: Text -> [(Text, Text)]
replaceEn s = [("2026-10-07-a.pt-BR.md", pt), ("2026-10-07-a.en.md", s)]

spec :: Env -> Spec
spec env = describe "news" $ do
  it "a post in both languages passes" $ do
    ok PtBr good "2026-10-07-a" `shouldNotBe` ""
    ok En good "2026-10-07-a" `shouldNotBe` ""
  it "pt-BR date and reading time" $
    ok PtBr good "2026-10-07-a"
      `shouldSatisfy` has "<time datetime=\"2026-10-07\">7 de outubro de 2026</time> · 1 min de leitura</p>"
  it "en date and reading time" $
    ok En good "2026-10-07-a" `shouldSatisfy` has "October 7, 2026</time> · 1 min read</p>"
  it "201 words round up to 2 minutes" $ do
    News.readingMinutes ["# t", T.replicate 200 "word "] `shouldBe` 2
    News.readingMinutes ["# t", T.replicate 199 "word "] `shouldBe` 1
  it "link targets and markup are not counted" $
    length (News.words' ["[two words](https://a.org/x/y/z)", "- **one** ·"]) `shouldBe` 3
  it "the paragraph after the date is the lede" $
    ok PtBr good "2026-10-07-a" `shouldSatisfy` has "<p class=\"lede\">um lede.</p>"
  it "a link's & is escaped once" $
    ok PtBr good "2026-10-07-a" `shouldSatisfy` has "<a href=\"https://x.org/?a=1&amp;b=2\">link</a>"
  it "bold and code render" $ do
    ok PtBr good "2026-10-07-a" `shouldSatisfy` has "<li><b>dois</b></li>"
    ok En good "2026-10-07-a" `shouldSatisfy` has "<code>code</code>"
  it "each language page shows only its own posts" $ do
    let pt' = ok PtBr good "2026-10-07-a"
        en' = ok En good "2026-10-07-a"
    (has "lang=\"pt-BR\"" pt' && not (has "lang=\"en\"" pt')) `shouldBe` True
    (has "lang=\"en\"" en' && not (has "lang=\"pt-BR\"" en')) `shouldBe` True
  it "a release card renders" $ do
    let html = ok En (replaceEn (en <> "\n" <> card <> "\n")) "2026-10-07-a"
    html `shouldSatisfy` has "href=\"https://github.com/marola-dev/marola/releases/tag/v0.2.1\">marola v0.2.1</a>"
    html `shouldSatisfy` has "October 8, 2026"
    html `shouldSatisfy` has "<p class=\"release-links\"><a href=\"https://x.org/n\">notes</a> · DOI</p>"
  fails "a release card with no links line fails" (replaceEn (en <> "\n::: release v0.2.1 2026-10-08\n- one\n")) "2026-10-07-a"
  fails "a post with no en file fails" [("2026-10-07-a.pt-BR.md", pt)] "2026-10-07-a"
  fails "a date line that is not the file's date fails" (replaceEn (T.replace "2026-10-07" "2026-10-08" en)) "2026-10-07-a"
  fails "a badly named file fails" (("post.en.md", en) : good) "2026-10-07-a"
  fails "an unsupported heading fails" (replaceEn (en <> "\n#### deep\n")) "2026-10-07-a"
  fails "leftover Markdown fails" (replaceEn (en <> "\n_italic_\n")) "2026-10-07-a"
  it "raw HTML is escaped, not passed through" $ do
    let html = ok En (replaceEn (en <> "\n<script>x</script>\n")) "2026-10-07-a"
    (has "&lt;script&gt;x&lt;/script&gt;" html && not (has "<script" html)) `shouldBe` True
  fails "a post missing from the README index fails" good ""
  it "two posts pass, newest first" $ do
    let newer =
          good
            <> [ ("2026-10-09-b.pt-BR.md", T.replace "2026-10-07" "2026-10-09" pt)
               , ("2026-10-09-b.en.md", T.replace "2026-10-07" "2026-10-09" en)
               ]
        html = ok En newer "2026-10-07-a 2026-10-09-b"
        at needle = T.length (fst (T.breakOn needle html))
    at "datetime=\"2026-10-09\"" `shouldSatisfy` (< at "datetime=\"2026-10-07\"")
  it "a sibling page link such as about.html is allowed and anything else relative is not" $ do
    let withLink url = replaceEn (T.replace "A lede." ("A [lede](" <> url <> ").") en)
    isRight (articles En (withLink "about.html") "2026-10-07-a") `shouldBe` True
    isLeft (articles En (withLink "../about") "2026-10-07-a") `shouldBe` True
  it "the news page of each language lists the repo's posts under the nav and the shared head" $
    mapM_
      ( \l -> do
          let html = renderWith env "news" l
          html `shouldSatisfy` has "aria-current=\"page\""
          html `shouldSatisfy` has "class=\"post-date\""
      )
      allLanguages
