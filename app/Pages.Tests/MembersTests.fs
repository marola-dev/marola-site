/// The cases of scripts/members_build.py's self-test, one for one (the avatar download and its file
/// sniffing stay in the Python: the F# build copies nothing from GitHub), plus the real members page.
module Marola.Pages.Tests.MembersTests

open System
open System.IO
open Expecto
open Marola
open Marola.Client
open Marola.Pages

let private sha = String.replicate 40 "a"

let private good =
    "# Members\n\n| Name | Affiliation | ORCID | GitHub | First commit |\n|---|---|---|---|---|\n"
    + "| Hoffmann, Matheus | Poli, UFRJ & co | [0009-0009-1056-7661](https://orcid.org/0009-0009-1056-7661)"
    + " | [h0ffmann](https://github.com/h0ffmann) | [2026-09-05](https://github.com/marola-dev/marola/commit/"
    + sha
    + ") |\n"
    + "| Soares da Silva Junior, Rob Kler | | | | |\n"

let private avatars = Map.ofList [ "h0ffmann", "h0ffmann.png" ]

let private parsed (text: string) : Member list =
    match Members.parse text with
    | Ok members -> members
    | Error e -> failwith e

let private page (language: Language) (text: string) : string =
    Vdom.toHtml (Members.article language avatars (parsed text))

let private has (needle: string) (html: string) = html.Contains needle

let private fails (label: string) (text: string) =
    test label { Expect.isError (Members.parse text) label }

let private count (needle: string) (html: string) =
    (html.Length - html.Replace(needle, "").Length) / needle.Length

let private roles =
    good
        .Replace(
            "| Name | Affiliation | ORCID | GitHub | First commit |\n|---|---|---|---|---|\n",
            "| Name | Affiliation | ORCID | GitHub | First commit | marola role | GitHub role |\n"
            + "|---|---|---|---|---|---|---|\n"
        )
        .Replace(") |\n|", ") | contributor | owner |\n|")
        .Replace(
            "| Soares da Silva Junior, Rob Kler | | | | |",
            "| Soares da Silva Junior, Rob Kler | | | | | ui / mkt | |"
        )

let private dated =
    "| Oliveira, Elisa | | | | [2026-10-01](https://github.com/marola-dev/x/commit/"
    + String.replicate 40 "b"
    + ") |\n"

let tests =
    testList
        "members"
        [ test "a well-formed MEMBERS.md passes, with the avatar of each GitHub login" {
              Expect.isOk (Members.parse good) "parse"
              Expect.isOk (Members.checkAvatars avatars (parsed good)) "avatars"

              Expect.isTrue
                  (has
                      "<img class=\"member-mark\" src=\"/img/members/h0ffmann.png\" width=\"48\" height=\"48\" alt=\"\""
                      (page Language.PtBr good))
                  "a member with a GitHub login shows the local avatar"
          }
          test "an avatar missing on disk fails" {
              Expect.isError (Members.checkAvatars Map.empty (parsed good)) "missing"
          }
          test "a stray avatar fails" {
              Expect.isError (Members.checkAvatars (Map.add "gone" "gone.png" avatars) (parsed good)) "stray"
          }
          test "humans.txt lists each member in order, empty cells left out" {
              let humans = Members.humans (parsed good)

              Expect.isTrue
                  (has
                      "Name: Matheus Hoffmann\nAffiliation: Poli, UFRJ & co\nGitHub: https://github.com/h0ffmann\nORCID: https://orcid.org/0009-0009-1056-7661\n"
                      humans
                   && has "Name: Rob Kler Soares da Silva Junior\n\n" humans)
                  "blocks"
          }
          test "one article per language" {
              Expect.equal (count "<article class=\"about-body\" lang=\"pt-BR\">" (page Language.PtBr good)) 1 "pt-BR"
              Expect.equal (count "<article class=\"about-body\" lang=\"en\">" (page Language.En good)) 1 "en"
          }
          test "'Family, Given' shows as Given Family" {
              Expect.isTrue (has "<span class=\"member-name\">Matheus Hoffmann</span>" (page Language.En good)) "name"
          }
          test "a compound family name" {
              Expect.isTrue
                  (has "<span class=\"member-name\">Rob Kler Soares da Silva Junior</span>" (page Language.En good))
                  "name"
          }
          test "a member with no GitHub login keeps initials (first and last word)" {
              let html = page Language.En good

              Expect.isTrue
                  (has "aria-hidden=\"true\">RJ</span>" html
                   && not (has "aria-hidden=\"true\">MH" html))
                  "initials"
          }
          test "ORCID and GitHub links" {
              let html = page Language.En good

              Expect.isTrue
                  (has "<a href=\"https://orcid.org/0009-0009-1056-7661\">ORCID 0009-0009-1056-7661</a>" html)
                  "orcid"

              Expect.isTrue (has "<a href=\"https://github.com/h0ffmann\">@h0ffmann</a>" html) "github"
          }
          test "the affiliation is escaped" {
              Expect.isTrue (has "Poli, UFRJ &amp; co" (page Language.En good)) "escaped"
          }
          test "empty cells render nothing" {
              let html = page Language.En good
              Expect.equal (count "member-aff" html) 1 "aff"
              Expect.equal (count "member-links" html) 1 "links"
          }
          test "MEMBERS.md's order is kept" {
              let html = page Language.En good
              Expect.isTrue (html.IndexOf "Matheus" < html.IndexOf "Rob Kler") "order"
          }
          test "the first commit links its commit" {
              Expect.isTrue
                  (has
                      ("<a href=\"https://github.com/marola-dev/marola/commit/"
                       + sha
                       + "\">first commit on 2026-09-05</a>")
                      (page Language.En good))
                  "commit"
          }
          fails "no table fails" "# Members\n"
          fails "a reordered header fails" (good.Replace("| Name | Affiliation |", "| Affiliation | Name |"))
          fails "a name without 'Family, Given' fails" (good.Replace("Hoffmann, Matheus", "Matheus Hoffmann"))
          fails "a malformed ORCID fails" (good.Replace("[0009-0009-1056-7661]", "[0009-0009-1056]"))
          fails
              "an ORCID whose link names another id fails"
              (good.Replace("orcid.org/0009-0009-1056-7661", "orcid.org/0009-0009-1056-7662"))
          fails "a bare GitHub login fails" (good.Replace("[h0ffmann](https://github.com/h0ffmann)", "h0ffmann"))
          fails "a row with a missing cell fails" (good + "| Oliveira, Elisa | | | |\n")
          fails
              "a first commit that is not a marola-dev commit URL fails"
              (good.Replace("marola-dev/marola/commit", "someone/else/commit"))
          fails "a dated row after an undated one fails" (good + dated)
          fails
              "rows out of first-commit order fail"
              (good.Replace(
                  "| Soares",
                  dated.Replace("2026-10-01", "2026-09-01").Replace("Oliveira, Elisa", "Ribeiro, Pablo")
                  + "| Soares"
              ))
          test "the header with the two role columns passes" { Expect.isOk (Members.parse roles) "parse" }
          test "the roles show in both languages, as MEMBERS.md writes them" {
              Expect.isTrue
                  (has "<span class=\"member-role\">marola: contributor · GitHub: owner</span>" (page Language.En roles))
                  "en"

              Expect.isTrue
                  (has
                      "<span class=\"member-role\">no marola: contributor · no GitHub: owner</span>"
                      (page Language.PtBr roles))
                  "pt-BR"
          }
          test "an empty GitHub role shows only the marola role" {
              Expect.isTrue (has "<span class=\"member-role\">marola: ui / mkt</span>" (page Language.En roles)) "role"
          }
          test "the legacy header shows no roles" { Expect.isFalse (has "member-role" (page Language.En good)) "none" }
          fails "an empty marola role fails" (roles.Replace("| ui / mkt |", "| |"))
          fails "a row with five cells under the role header fails" (roles + "| Oliveira, Elisa | | | | |\n")
          fails
              "a table with no rows fails"
              "| Name | Affiliation | ORCID | GitHub | First commit |\n|---|---|---|---|---|\n"
          test "the real avatars are the ones the real members list" {
              // The repo's img/members/ has one file per login of the page the old builder wrote.
              let members = parsed Support.membersTable
              Expect.isOk (Members.checkAvatars Support.env.Avatars members) "avatars"
          }
          test "blobId is what git hash-object prints" {
              // `printf '' | git hash-object --stdin` and `printf 'hello\n' | git hash-object --stdin`.
              Expect.equal (Members.blobId [||]) "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391" "empty"

              Expect.equal
                  (Members.blobId (Text.Encoding.UTF8.GetBytes "hello\n"))
                  "ce013625030ba8dba906f756967f9e9ca394464a"
                  "hello"
          }
          test "the pin's blob line is its second line" {
              let blob = String.replicate 40 "b"
              Expect.equal (Members.pinnedBlob (sha + "\nblob " + blob + "\n")) (Some blob) "two lines"
              Expect.equal (Members.pinnedBlob (sha + "\n")) None "no second line"
              Expect.equal (Members.pinnedBlob (sha + "\nblob xyz\n")) None "not a blob id"
              Expect.equal (Members.pinnedBlob (sha + "\n" + sha + "\n")) None "a bare sha is not a blob line"
          }
          test "a vendored copy that does not hash to the pin is an error, a matching one is its text" {
              let bytes = Text.Encoding.UTF8.GetBytes good
              let pin (blob: string) = sha + "\nblob " + blob + "\n"
              Expect.equal (Members.vendored (pin (Members.blobId bytes)) bytes) (Ok good) "match"
              Expect.isError (Members.vendored (pin (String.replicate 40 "0")) bytes) "drift"
              Expect.isError (Members.vendored (sha + "\n") bytes) "no blob line"
          }
          test "site/members/MEMBERS.md is the blob site/members.version pins, and it parses" {
              let version =
                  File.ReadAllText(Path.Combine(Support.root, "site", "members.version"))

              let bytes =
                  File.ReadAllBytes(Path.Combine(Support.root, "site", "members", "MEMBERS.md"))

              match Members.vendored version bytes with
              | Error e -> failwith e
              | Ok text -> Expect.isOk (Members.parse text) "parse"
          } ]
