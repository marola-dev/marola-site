module Main (main) where

import Data.Text qualified as T
import Marola.Tools.DesignCheck qualified as DesignCheck
import Marola.Tools.ElmFixtures (elmString)
import Marola.Tools.JsCheck (Entry (..), check, parse)
import Test.Hspec

main :: IO ()
main = hspec $ do
  describe "design-check" $
    it "fails each rule on its bad fixture and passes the good pair" $
      DesignCheck.selfTest `shouldReturn` True
  describe "elm-fixtures" $ do
    it "escapes what an Elm string literal cannot hold" $
      elmString "a\"b\\c\nd\te\r\x01" `shouldBe` "\"a\\\"b\\\\c\\nd\\te\\r\\u{0001}\""
    it "keeps every other character as it is" $
      elmString "Itapuã — ok" `shouldBe` "\"Itapuã — ok\""
  describe "js-check" $ do
    let entries = [Entry "front/ports.js" "the ports Elm needs", Entry "front/public/vendor/" "vendored MapLibre and PMTiles"]
    it "passes listed files and vendored folders" $
      check entries ["front/ports.js", "front/public/vendor/maplibre/maplibre-gl.mjs", "README.md"] `shouldBe` []
    it "fails a JavaScript file that is not listed" $
      check entries ["front/ports.js", "front/public/vendor/x.js", "scripts/new.mjs"] `shouldSatisfy` any (T.isInfixOf "not allowed: scripts/new.mjs")
    it "fails an entry that matches no file" $
      check entries ["front/public/vendor/x.js"] `shouldSatisfy` any (T.isInfixOf "unused entry: front/ports.js")
    it "refuses an entry with no reason" $
      parse "front/ports.js\t\n" `shouldSatisfy` either (const True) (const False)
    it "skips comments and blank lines" $
      parse "# why\n\nfront/ports.js\tthe ports Elm needs\n" `shouldBe` Right [Entry "front/ports.js" "the ports Elm needs"]
