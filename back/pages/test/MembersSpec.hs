-- | The cases of scripts/members_build.py's self-test, one for one (the avatar download stays in the
-- Python), plus the real members page and the pinned copy.
module MembersSpec (spec) where

import Data.ByteString qualified as B
import Data.Either (isLeft, isRight)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Marola.Pages.Html (toHtml)
import Marola.Pages.Language (Language (..))
import Marola.Pages.Loader (readText)
import Marola.Pages.Members (Member)
import Marola.Pages.Members qualified as Members
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

-- The header with the Website column (MEMBERS.md, 25 November 2026).
full :: Text
full =
  "# Members\n\n| Name | Affiliation | ORCID | GitHub | Website | First commit | marola role | GitHub role |\n"
    <> "|---|---|---|---|---|---|---|---|\n"
    <> "| Hoffmann, Matheus | Poli, UFRJ & co | [0009-0009-1056-7661](https://orcid.org/0009-0009-1056-7661)"
    <> " | [h0ffmann](https://github.com/h0ffmann)"
    <> " | https://hffmnn.piabrota.art/ https://www.instagram.com/nader_oficial/"
    <> " | [2026-09-05](https://github.com/marola-dev/marola/commit/"
    <> sha
    <> ") | contributor | owner |\n"
    <> "| Soares da Silva Junior, Rob Kler | | | | | | ui / mkt | |\n"

avatars :: Map.Map Text Text
avatars = Map.fromList [("h0ffmann", "h0ffmann.png")]

-- The row with a local photo and no GitHub login (MEMBERS.md, 26 November 2026).
local :: Text
local =
  full
    <> "| Almeida, Bárbara | TV Integração | | | https://www.instagram.com/barbaraalmeidajn/"
    <> " | | advisor | |\n"

localAvatars :: Map.Map Text Text
localAvatars = Map.insert "barbara-almeida" "barbara-almeida.jpg" avatars

-- The ## Non-human table (MEMBERS.md, 25 November 2026), under the people's table.
entityTable :: Text
entityTable =
  full
    <> "\n## Non-human\n\n| Name | GitHub | Website |\n|---|---|---|\n"
    <> "| Piabrota | [piabrota](https://github.com/piabrota) | https://piabrota.art/ |\n"
    <> "| Ouroboric | [ouroboric-dev](https://github.com/ouroboric-dev) | https://ouroboric.dev/ |\n"

-- The header with the State column (MEMBERS.md, 25 November 2026).
states :: Text
states =
  "# Members\n\n| Name | Affiliation | State | ORCID | GitHub | Website | First commit | marola role | GitHub role |\n"
    <> "|---|---|---|---|---|---|---|---|---|\n"
    <> "| Hoffmann, Matheus | Piabrota ART | Rio de Janeiro / Santa Catarina"
    <> " | [0009-0009-1056-7661](https://orcid.org/0009-0009-1056-7661)"
    <> " | [h0ffmann](https://github.com/h0ffmann) | https://hffmnn.piabrota.art/"
    <> " | [2026-09-05](https://github.com/marola-dev/marola/commit/"
    <> sha
    <> ") | contributor | owner |\n"
    <> "| Soares da Silva Junior, Rob Kler | | Minas Gerais / Rio de Janeiro | | | | | ui / mkt | |\n"

parsed :: Text -> [Member]
parsed s = either (error . T.unpack) id (Members.parse s)

entities :: Text -> [Members.Entity]
entities s = either (error . T.unpack) id (Members.parseEntities s)

page :: Language -> Text -> Text
page l s = toHtml (Members.article l avatars (parsed s) (entities s))

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
    Members.checkAvatars avatars (parsed good) [] `shouldBe` Right ()
    page PtBr good
      `shouldSatisfy` has "<img class=\"member-mark\" src=\"/img/members/h0ffmann.png\" width=\"48\" height=\"48\" alt=\"\""
  it "an avatar missing on disk fails" $
    isLeft (Members.checkAvatars Map.empty (parsed good) []) `shouldBe` True
  it "a stray avatar fails" $
    isLeft (Members.checkAvatars (Map.insert "gone" "gone.png" avatars) (parsed good) []) `shouldBe` True
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
  it "a member with no GitHub login and a local photo shows it instead of initials" $ do
    let html = toHtml (Members.article PtBr localAvatars (parsed local) [])
    html `shouldSatisfy` has "<img class=\"member-mark\" src=\"/img/members/barbara-almeida.jpg\" width=\"48\" height=\"48\" alt=\"\""
    html `shouldNotSatisfy` has "aria-hidden=\"true\">BA</span>"
    Members.checkAvatars localAvatars (parsed local) [] `shouldBe` Right ()
  it "a local photo for a member with a GitHub login is a stray" $
    isLeft (Members.checkAvatars (Map.insert "matheus-hoffmann" "matheus-hoffmann.jpg" avatars) (parsed full) []) `shouldBe` True
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
  it "the header with the Website column passes" $ isRight (Members.parse full) `shouldBe` True
  it "one or two websites are links in the card, shown without the scheme" $
    page En full
      `shouldSatisfy` has
        ( "<a href=\"https://hffmnn.piabrota.art/\">hffmnn.piabrota.art</a>"
            <> " <a href=\"https://www.instagram.com/nader_oficial/\">www.instagram.com/nader_oficial</a>"
        )
  it "humans.txt lists the websites" $
    Members.humans (parsed full)
      `shouldSatisfy` has
        ( "GitHub: https://github.com/h0ffmann\nORCID: https://orcid.org/0009-0009-1056-7661\n"
            <> "Website: https://hffmnn.piabrota.art/\nWebsite: https://www.instagram.com/nader_oficial/\n"
        )
  fails "a website that is not https fails" (T.replace "https://hffmnn.piabrota.art/" "http://hffmnn.piabrota.art/" full)
  fails "a third website fails" (T.replace "https://www.instagram.com/nader_oficial/" "https://a.example/ https://b.example/ https://c.example/" full)
  fails "a website without a dotted host fails" (T.replace "https://hffmnn.piabrota.art/" "https://localhost/" full)
  fails "an empty marola role fails" (T.replace "| ui / mkt |" "| |" roles)
  it "the non-human table passes, with an avatar of its own" $ do
    let all3 = Map.fromList [("h0ffmann", "h0ffmann.png"), ("piabrota", "piabrota.png"), ("ouroboric-dev", "ouroboric-dev.png")]
    Members.checkAvatars all3 (parsed entityTable) (entities entityTable) `shouldBe` Right ()
    isLeft (Members.checkAvatars avatars (parsed entityTable) (entities entityTable)) `shouldBe` True
  it "the non-human section is headed in each language" $ do
    page PtBr entityTable `shouldSatisfy` has "<h2>não humanos</h2>"
    page En entityTable `shouldSatisfy` has "<h2>non-human</h2>"
  it "a non-human card is its site first, then its GitHub login" $
    page En entityTable
      `shouldSatisfy` has
        ( "<a href=\"https://piabrota.art/\">piabrota.art</a>"
            <> " <a href=\"https://github.com/piabrota\">@piabrota</a>"
        )
  it "the non-human rows stay out of humans.txt" $
    Members.humans (parsed entityTable) `shouldNotSatisfy` has "Piabrota"
  it "a non-human row whose site is empty fails" $
    isLeft (Members.parseEntities (T.replace "| https://piabrota.art/ |" "| |" entityTable)) `shouldBe` True
  it "a non-human row without a GitHub login fails" $
    isLeft (Members.parseEntities (T.replace "[piabrota](https://github.com/piabrota)" "piabrota" entityTable)) `shouldBe` True
  it "an empty non-human table fails" $
    isLeft (Members.parseEntities "| Name | GitHub | Website |\n|---|---|---|\n") `shouldBe` True
  it "the header with the State column passes" $ isRight (Members.parse states) `shouldBe` True
  it "the state shows on the card, as MEMBERS.md spells it" $
    page En states `shouldSatisfy` has "<span class=\"member-state\">Rio de Janeiro / Santa Catarina</span>"
  it "humans.txt lists the state" $
    Members.humans (parsed states)
      `shouldSatisfy` has "Affiliation: Piabrota ART\nState: Rio de Janeiro / Santa Catarina\n"
  it "a state as a two-letter code fails" $
    isLeft (Members.parse (T.replace "Rio de Janeiro / Santa Catarina" "RJ/FL" states)) `shouldBe` True
  it "a state that is not Brazilian fails" $
    isLeft (Members.parse (T.replace "Minas Gerais / Rio de Janeiro" "Minas Gerais / Atlantis" states)) `shouldBe` True
  it "three states fail" $
    isLeft (Members.parse (T.replace "Minas Gerais / Rio de Janeiro" "Minas Gerais / Rio de Janeiro / Bahia" states)) `shouldBe` True
  fails "a row with five cells under the role header fails" (roles <> "| Oliveira, Elisa | | | | |\n")
  fails "a table with no rows fails" "| Name | Affiliation | ORCID | GitHub | First commit |\n|---|---|---|---|---|\n"
  it "the real avatars are the ones the real members list" $ do
    table <- membersTable
    Members.checkAvatars (envAvatars env) (parsed table) (entities table) `shouldBe` Right ()
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
