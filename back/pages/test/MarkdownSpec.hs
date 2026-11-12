module MarkdownSpec (spec) where

import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Pages.Html (toHtml)
import Marola.Pages.Markdown qualified as Markdown
import Test.Hspec

hd :: Text
hd = "title: t\ndescription: d\n\n"

body :: Text -> Text
body s = either (error . T.unpack) (T.concat . map toHtml . Markdown.body) (Markdown.parse (hd <> s))

fails :: Text -> Bool
fails s = isLeft (Markdown.parse (hd <> s))

spec :: Spec
spec = describe "Markdown" $ do
  it "headings, paragraphs that wrap, lists and inline marks" $
    body "## one\n\ntwo\nlines with `code` and **bold** and [a link](https://x.org/?a=1&b=2)\n\n- first\n- second"
      `shouldBe` "<h2>one</h2><p>two lines with <code>code</code> and <b>bold</b> and <a href=\"https://x.org/?a=1&amp;b=2\">a link</a></p><ul><li>first</li><li>second</li></ul>"
  it "a lede, a quote with a language and a source, a figure, a disabled item" $
    body "::lede big\n\n> @en\n> \"q\"\n> -- by [me](/x)\n\n![alt \"a\"](/img/a.svg 10x20)\ncaption\n\n- {{soon Coffee|soon}}"
      `shouldBe` "<p class=\"lede\">big</p><blockquote lang=\"en\"><p>\"q\"</p><footer>by <a href=\"/x\">me</a></footer></blockquote><figure><a href=\"/img/a.svg\"><img src=\"/img/a.svg\" width=\"10\" height=\"20\" alt=\"alt &quot;a&quot;\"></a><figcaption>caption</figcaption></figure><ul><li><span aria-disabled=\"true\">Coffee <i>soon</i></span></li></ul>"
  it "a comment line is dropped" $ body "%% note\n\ntext" `shouldBe` "<p>text</p>"
  it "text that looks like markup stays text" $
    body "a <script>x</script> b" `shouldBe` "<p>a &lt;script&gt;x&lt;/script&gt; b</p>"
  it "what the subset does not have is an error, not output" $ do
    fails "[x](javascript:alert(1))" `shouldBe` True
    fails "[x](//evil.example/)" `shouldBe` True
    fails "<div>x</div>" `shouldBe` True
    fails "#### deep" `shouldBe` True
    fails "_italic_ and *star*" `shouldBe` True
    fails "an `unclosed code" `shouldBe` True
    fails "- one\n  wraps" `shouldBe` True
  it "a page without title and description is an error" $
    isLeft (Markdown.parse "## only a heading") `shouldBe` True
