module Main (main) where

import qualified EqualitySpec
import qualified HtmlSpec
import qualified MarkdownSpec
import qualified MembersSpec
import qualified MetaSpec
import qualified NewsSpec
import qualified PageSpec
import Support (loadEnv)
import Test.Hspec

main :: IO ()
main = do
  env <- loadEnv
  hspec $ do
    HtmlSpec.spec
    MarkdownSpec.spec
    NewsSpec.spec env
    MembersSpec.spec env
    MetaSpec.spec env
    EqualitySpec.spec env
    PageSpec.spec env
