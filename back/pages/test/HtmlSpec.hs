module HtmlSpec (spec) where

import Marola.Pages.Html
import Test.Hspec

spec :: Spec
spec = describe "toHtml" $ do
  it "text keeps no markup" $
    toHtml (el "p" [] [text "<script>alert(\"x\")</script> & co"])
      `shouldBe` "<p>&lt;script&gt;alert(\"x\")&lt;/script&gt; &amp; co</p>"
  it "an attribute value cannot end its quote" $
    toHtml (el "a" [attr "href" "/a?b=1&c=\"><script>"] [])
      `shouldBe` "<a href=\"/a?b=1&amp;c=&quot;&gt;&lt;script&gt;\"></a>"
  it "a void element has no closing tag, an empty one has" $
    toHtml (el "div" [] [el "img" [attr "alt" ""] [], el "span" [] []])
      `shouldBe` "<div><img alt=\"\"><span></span></div>"
  it "flags print as bare names, false flags vanish" $
    toHtml (el "button" [Flag "disabled" True, Flag "hidden" False] [])
      `shouldBe` "<button disabled></button>"
  it "svg children keep their closing tags" $
    toHtml (svg "svg" [attr "viewBox" "0 0 1 1"] [svg "path" [attr "d" "M0 0"] []])
      `shouldBe` "<svg viewBox=\"0 0 1 1\"><path d=\"M0 0\"></path></svg>"
