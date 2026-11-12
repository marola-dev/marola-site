module Main (main) where

import EqualitySpec qualified
import HtmlSpec qualified
import MarkdownSpec qualified
import MembersSpec qualified
import MetaSpec qualified
import NewsSpec qualified
import PageSpec qualified
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
