-- | The cases of scripts/members_build.py's self-test, one for one (the avatar download stays in the
-- Python), plus the real members page and the pinned copy.
module MembersSpec (spec) where

import qualified Data.ByteString as B
import Data.Either (isLeft, isRight)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Marola.Pages.Html (toHtml)
import Marola.Pages.Language (Language (..))
import Marola.Pages.Loader (readText)
import Marola.Pages.Members (Member)
import qualified Marola.Pages.Members as Members
import Marola.Pages.Site (Env (..))
import Support
import System.FilePath ((</>))
import Test.Hspec

sha :: Text
sha = T.replicate 40 "a"

good :: Text
good =
  "# Members\n\n| Name | Affiliation | ORCID | GitHub | First commit |\n|---|---|---|---|---|\n"
    <> "| Hoffmann, Matheus | Poli, UFRJ & co | [0009-0009-1056-7661](https://orcid.org/0009-0009-1056-7661)"
    <> " | [h0ffmann](https://github.com/h0ffmann) | [2026-09-05](https://github.com/marola-dev/marola/commit/"
    <> sha
    <> ") |\n"
    <> "| Soares da Silva Junior, Rob Kler | | | | |\n"

avatars :: Map.Map Text Text
avatars = Map.fromList [("h0ffmann", "h0ffmann.png")]

parsed :: Text -> [Member]
parsed s = either (error . T.unpack) id (Members.parse s)

page :: Language -> Text -> Text
page l s = toHtml (Members.article l avatars (parsed s))

fails :: String -> Text -> Spec
fails label s = it label (isLeft (Members.parse s) `shouldBe` True)

roles :: Text
roles =
  T.replace "| Soares da Silva Junior, Rob Kler | | | | |" "| Soares da Silva Junior, Rob Kler | | | | | ui / mkt | |"
    . T.replace ") |\n|" ") | contributor | owner |\n|"
    . T.replace
      "| Name | Affiliation | ORCID | GitHub | First commit |\n|---|---|---|---|---|\n"
      ( "| Name | Affiliation | ORCID | GitHub | First commit | marola role | GitHub role |\n"
          <> "|---|---|---|---|---|---|---|\n"
      )
    $ good

dated :: Text
dated =
  "| Oliveira, Elisa | | | | [2026-10-01](https://github.com/marola-dev/x/commit/"
    <> T.replicate 40 "b"
    <> ") |\n"

spec :: Env -> Spec
spec env = describe "members" $ do
  it "a well-formed MEMBERS.md passes, with the avatar of each GitHub login" $ do
    isRight (Members.parse good) `shouldBe` True
    Members.checkAvatars avatars (parsed good) `shouldBe` Right ()
    page PtBr good
      `shouldSatisfy` has "<img class=\"member-mark\" src=\"/img/members/h0ffmann.png\" width=\"48\" height=\"48\" alt=\"\""
  it "an avatar missing on disk fails" $
    isLeft (Members.checkAvatars Map.empty (parsed good)) `shouldBe` True
  it "a stray avatar fails" $
    isLeft (Members.checkAvatars (Map.insert "gone" "gone.png" avatars) (parsed good)) `shouldBe` True
  it "humans.txt lists each member in order, empty cells left out" $ do
    let humans = Members.humans (parsed good)
    humans
      `shouldSatisfy` has "Name: Matheus Hoffmann\nAffiliation: Poli, UFRJ & co\nGitHub: https://github.com/h0ffmann\nORCID: https://orcid.org/0009-0009-1056-7661\n"
    humans `shouldSatisfy` has "Name: Rob Kler Soares da Silva Junior\n\n"
  it "one article per language" $ do
    count "<article class=\"about-body\" lang=\"pt-BR\">" (page PtBr good) `shouldBe` 1
    count "<article class=\"about-body\" lang=\"en\">" (page En good) `shouldBe` 1
  it "'Family, Given' shows as Given Family" $
    page En good `shouldSatisfy` has "<span class=\"member-name\">Matheus Hoffmann</span>"
  it "a compound family name" $
    page En good `shouldSatisfy` has "<span class=\"member-name\">Rob Kler Soares da Silva Junior</span>"
  it "a member with no GitHub login keeps initials (first and last word)" $ do
    let html = page En good
    (has "aria-hidden=\"true\">RJ</span>" html && not (has "aria-hidden=\"true\">MH" html)) `shouldBe` True
  it "ORCID and GitHub links" $ do
    let html = page En good
    html `shouldSatisfy` has "<a href=\"https://orcid.org/0009-0009-1056-7661\">ORCID 0009-0009-1056-7661</a>"
    html `shouldSatisfy` has "<a href=\"https://github.com/h0ffmann\">@h0ffmann</a>"
  it "the affiliation is escaped" $ page En good `shouldSatisfy` has "Poli, UFRJ &amp; co"
  it "empty cells render nothing" $ do
    count "member-aff" (page En good) `shouldBe` 1
    count "member-links" (page En good) `shouldBe` 1
  it "MEMBERS.md's order is kept" $ do
    let html = page En good
        at needle = T.length (fst (T.breakOn needle html))
    at "Matheus" `shouldSatisfy` (< at "Rob Kler")
  it "the first commit links its commit" $
    page En good
      `shouldSatisfy` has ("<a href=\"https://github.com/marola-dev/marola/commit/" <> sha <> "\">first commit on 2026-09-05</a>")
  fails "no table fails" "# Members\n"
  fails "a reordered header fails" (T.replace "| Name | Affiliation |" "| Affiliation | Name |" good)
  fails "a name without 'Family, Given' fails" (T.replace "Hoffmann, Matheus" "Matheus Hoffmann" good)
  fails "a malformed ORCID fails" (T.replace "[0009-0009-1056-7661]" "[0009-0009-1056]" good)
  fails "an ORCID whose link names another id fails" (T.replace "orcid.org/0009-0009-1056-7661" "orcid.org/0009-0009-1056-7662" good)
  fails "a bare GitHub login fails" (T.replace "[h0ffmann](https://github.com/h0ffmann)" "h0ffmann" good)
  fails "a row with a missing cell fails" (good <> "| Oliveira, Elisa | | | |\n")
  fails "a first commit that is not a marola-dev commit URL fails" (T.replace "marola-dev/marola/commit" "someone/else/commit" good)
  fails "a dated row after an undated one fails" (good <> dated)
  fails
    "rows out of first-commit order fail"
    (T.replace "| Soares" (T.replace "Oliveira, Elisa" "Ribeiro, Pablo" (T.replace "2026-10-01" "2026-09-01" dated) <> "| Soares") good)
  it "the header with the two role columns passes" $ isRight (Members.parse roles) `shouldBe` True
  it "the roles show in both languages, as MEMBERS.md writes them" $ do
    page En roles `shouldSatisfy` has "<span class=\"member-role\">marola: contributor · GitHub: owner</span>"
    page PtBr roles `shouldSatisfy` has "<span class=\"member-role\">no marola: contributor · no GitHub: owner</span>"
  it "an empty GitHub role shows only the marola role" $
    page En roles `shouldSatisfy` has "<span class=\"member-role\">marola: ui / mkt</span>"
  it "the legacy header shows no roles" $ page En good `shouldNotSatisfy` has "member-role"
  fails "an empty marola role fails" (T.replace "| ui / mkt |" "| |" roles)
  fails "a row with five cells under the role header fails" (roles <> "| Oliveira, Elisa | | | | |\n")
  fails "a table with no rows fails" "| Name | Affiliation | ORCID | GitHub | First commit |\n|---|---|---|---|---|\n"
  it "the real avatars are the ones the real members list" $ do
    members <- parsed <$> membersTable
    Members.checkAvatars (envAvatars env) members `shouldBe` Right ()
  it "blobId is what git hash-object prints" $ do
    Members.blobId B.empty `shouldBe` "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
    Members.blobId (TE.encodeUtf8 "hello\n") `shouldBe` "ce013625030ba8dba906f756967f9e9ca394464a"
  it "the pin's blob line is its second line" $ do
    let blob = T.replicate 40 "b"
    Members.pinnedBlob (sha <> "\nblob " <> blob <> "\n") `shouldBe` Just blob
    Members.pinnedBlob (sha <> "\n") `shouldBe` Nothing
    Members.pinnedBlob (sha <> "\nblob xyz\n") `shouldBe` Nothing
    Members.pinnedBlob (sha <> "\n" <> sha <> "\n") `shouldBe` Nothing
  it "a vendored copy that does not hash to the pin is an error, a matching one is its text" $ do
    let bytes = TE.encodeUtf8 good
        pin blob = sha <> "\nblob " <> blob <> "\n"
    Members.vendored (pin (Members.blobId bytes)) bytes `shouldBe` Right good
    isLeft (Members.vendored (pin (T.replicate 40 "0")) bytes) `shouldBe` True
    isLeft (Members.vendored (sha <> "\n") bytes) `shouldBe` True
  it "site/members/MEMBERS.md is the blob site/members.version pins, and it parses" $ do
    r <- root
    version <- readText (r </> "site" </> "members.version")
    bytes <- B.readFile (r </> "site" </> "members" </> "MEMBERS.md")
    case Members.vendored version bytes of
      Left e -> expectationFailure (T.unpack e)
      Right txt -> isRight (Members.parse txt) `shouldBe` True
