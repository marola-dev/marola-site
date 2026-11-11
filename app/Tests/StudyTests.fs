/// Study validation, the ORCID check digit and the JSON a study answers with.
module Marola.Tests.StudyTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola
open Marola.Study

let private good =
    Map.ofList
        [ "title", "Enterococcus in Praia do Leblon, 2025"
          "authors", "Ana Silva | 0000-0002-1825-0097\nBruno Costa"
          "abstract", String.replicate 12 "Sampling of bathing water. "
          "area", "rio"
          "topic", "water-quality"
          "sources", "https://www.inea.rj.gov.br/balneabilidade\nhttps://example.org/data"
          "repository", "https://github.com/example/leblon"
          "rights", "true"
          "ai_contribution", "none" ]

let private run (fields: Map<string, string>) =
    validate (fun k -> Map.tryFind k fields)

let private codes (fields: Map<string, string>) =
    match run fields with
    | Ok _ -> []
    | Error es -> es |> List.map (fun e -> e.Field, e.Code)

let private has (items: (string * string) list) (item: string * string) (msg: string) =
    Expect.isTrue (List.contains item items) msg

let private with' k v (m: Map<string, string>) = Map.add k v m

let private record status =
    match run good with
    | Ok s ->
        { Id = "abcdefghij"
          ReceivedUtc = "2026-11-11T10:00:00Z"
          Sha256 = String.replicate 64 "a"
          Submission = s
          AuthorLogin = "ana"
          AuthorGithubId = 42L
          Status = status
          HiddenReason = Some "wrong unit"
          HiddenUtc = Some "2026-11-12T10:00:00Z" }
    | Error _ -> failwith "good fixture is invalid"

let tests =
    testList
        "study"
        [ testCase "a complete submission is valid and the licence defaults to CC-BY-4.0"
          <| fun () ->
              match run good with
              | Ok s ->
                  Expect.equal s.Licence CcBy40 "default licence"
                  Expect.equal (List.length s.Authors) 2 "two authors"
                  Expect.equal s.Authors.[0].Orcid (Some "0000-0002-1825-0097") "orcid"
                  Expect.equal s.Authors.[1].Orcid None "no orcid"
                  Expect.equal (List.length s.Sources) 2 "two sources"
              | Error es -> failwithf "unexpected errors: %A" es

          testCase "ORCID check digit: known good ids pass, a wrong digit fails"
          <| fun () ->
              Expect.isTrue (validOrcid "0000-0002-1825-0097") "docs example"
              Expect.isTrue (validOrcid "0000-0001-5109-3700") "docs example 2"
              Expect.isTrue (validOrcid "0000-0002-1694-233X") "X check"
              Expect.isFalse (validOrcid "0000-0002-1825-0098") "wrong check digit"
              Expect.isFalse (validOrcid "0000-0002-1694-2330") "X replaced"
              Expect.isFalse (validOrcid "0000-0002-1825-009") "short"
              Expect.isFalse (validOrcid "0000000218250097") "no dashes"
              Expect.isFalse (validOrcid "0000-0002-1825-009x") "lower case x"

          testCase "every error comes at once with a machine code"
          <| fun () ->
              let all = codes (Map.ofList [ "rights", "false"; "area", "mars" ])

              for expected in
                  [ "title", "required"
                    "authors", "required"
                    "abstract", "required"
                    "area", "unknown_value"
                    "topic", "required"
                    "rights", "must_be_true"
                    "ai_contribution", "required" ] do
                  has all expected "error present"

          testCase "length bounds are inclusive"
          <| fun () ->
              Expect.isEmpty (codes (good |> with' "title" (String.replicate 5 "a"))) "5 ok"
              Expect.isEmpty (codes (good |> with' "title" (String.replicate 200 "a"))) "200 ok"
              has (codes (good |> with' "title" (String.replicate 4 "a"))) ("title", "too_short") "4"
              has (codes (good |> with' "title" (String.replicate 201 "a"))) ("title", "too_long") "201"
              Expect.isEmpty (codes (good |> with' "abstract" (String.replicate 100 "a"))) "100 ok"
              has (codes (good |> with' "abstract" (String.replicate 99 "a"))) ("abstract", "too_short") "99"
              has (codes (good |> with' "abstract" (String.replicate 4001 "a"))) ("abstract", "too_long") "4001"

          testCase "a title with a line break is refused"
          <| fun () -> has (codes (good |> with' "title" "first line\nsecond line")) ("title", "invalid") "newline"

          testCase "authors: 20 pass, 21 fail, a short name and a bad ORCID fail"
          <| fun () ->
              let n k =
                  [ for i in 1..k -> "Author Number" + string i ] |> String.concat "\n"

              Expect.isEmpty (codes (good |> with' "authors" (n 20))) "20"
              has (codes (good |> with' "authors" (n 21))) ("authors", "too_many") "21"
              has (codes (good |> with' "authors" "A")) ("authors", "bad_name") "short name"

              has
                  (codes (good |> with' "authors" "Ana Silva | 0000-0002-1825-0098"))
                  ("authors", "bad_orcid")
                  "bad check digit"

          testCase "sources: https only, at most 10"
          <| fun () ->
              let links k =
                  [ for i in 1..k -> "https://example.org/" + string i ] |> String.concat "\n"

              Expect.isEmpty (codes (good |> with' "sources" (links 10))) "10"
              Expect.isEmpty (codes (good |> with' "sources" "")) "none"
              has (codes (good |> with' "sources" (links 11))) ("sources", "too_many") "11"
              has (codes (good |> with' "sources" "http://example.org/a")) ("sources", "bad_link") "http"
              has (codes (good |> with' "sources" "javascript:alert(1)")) ("sources", "bad_link") "js"
              has (codes (good |> with' "sources" "mailto:a@b.c")) ("sources", "bad_link") "mailto"
              has (codes (good |> with' "repository" "ftp://x.org/r")) ("repository", "bad_link") "ftp"

          testCase "licence: closed licences are refused"
          <| fun () ->
              Expect.isEmpty (codes (good |> with' "licence" "CC0-1.0")) "cc0"
              has (codes (good |> with' "licence" "CC-BY-NC-4.0")) ("licence", "unknown_value") "nc"
              has (codes (good |> with' "licence" "All rights reserved")) ("licence", "unknown_value") "closed"

          testCase "rights must be true"
          <| fun () ->
              has (codes (Map.remove "rights" good)) ("rights", "must_be_true") "missing"
              has (codes (good |> with' "rights" "no")) ("rights", "must_be_true") "no"

          testCase "ai_process is required unless the contribution is none"
          <| fun () ->
              let level = good |> with' "ai_contribution" "drafting"
              has (codes level) ("ai_process", "required") "required"
              Expect.isEmpty (codes (level |> with' "ai_process" "Drafted with a model, edited by hand.")) "given"
              has (codes (level |> with' "ai_process" (String.replicate 1501 "a"))) ("ai_process", "too_long") "long"
              has (codes (good |> with' "ai_contribution" "magic")) ("ai_contribution", "unknown_value") "unknown"
              has (codes (good |> with' "ai_models" (String.replicate 301 "a"))) ("ai_models", "too_long") "models"

          testCase "control characters are stripped, newline and tab stay"
          <| fun () ->
              Expect.equal (cleanText "a\u0000b\u001bc\rd\u007fe\u0085f") "abcdef" "stripped"
              Expect.equal (cleanText "  a\nb\tc  ") "a\nb\tc" "kept and trimmed"

          testCase "every level has a name that parses back and a meaning"
          <| fun () ->
              Expect.equal (List.length levelValues) 6 "six levels"

              for name in levelValues do
                  match parseLevel name with
                  | Some l ->
                      Expect.equal (levelName l) name "round trip"
                      Expect.isNotEmpty (levelMeaning l) "meaning"
                  | None -> failwith name

          testCase "ids and hashes: shape only"
          <| fun () ->
              Expect.isTrue (validId "abcdefg234") "id"
              Expect.isFalse (validId "abcdefg23") "short"
              Expect.isFalse (validId "ABCDEFG234") "upper case"
              Expect.isFalse (validId "../../etc/") "path"
              Expect.isFalse (validId "abcdefg231") "1 is not base32"
              Expect.isTrue (validSha256 (String.replicate 64 "0")) "hash"
              Expect.isFalse (validSha256 (String.replicate 64 "G")) "not hex"

          testCase "JSON text escapes quotes, controls and markup"
          <| fun () ->
              Expect.equal
                  (render (JString "a\"b\\c\n<&>\u0001"))
                  "\"a\\\"b\\\\c\\n\\u003c\\u0026\\u003e\\u0001\""
                  "escaped"

              Expect.equal
                  (render (JObject [ "k", JArray [ JInt 1L; JNull; JBool true ] ]))
                  "{\"k\":[1,null,true]}"
                  "shape"

          testCase "a public record carries the notice, the hash, the date and the file link"
          <| fun () ->
              let json = render (recordJson (record Public))
              Expect.stringContains json "\"review\":\"not reviewed\"" "review"
              Expect.stringContains json "Not medical advice" "notice"
              Expect.stringContains json (String.replicate 64 "a") "hash"
              Expect.stringContains json "2026-11-11T10:00:00Z" "date"
              Expect.stringContains json "\"pdf_url\":\"/studies/abcdefghij.pdf\"" "pdf"

          testCase "a tombstone has id, hash, date, status and reason, and no text and no file link"
          <| fun () ->
              let json = render (recordJson (record Hidden))
              Expect.stringContains json "\"status\":\"hidden\"" "status"
              Expect.stringContains json "wrong unit" "reason"
              Expect.stringContains json (String.replicate 64 "a") "hash"
              Expect.stringContains json "2026-11-11T10:00:00Z" "date"
              Expect.isFalse (json.Contains "Enterococcus") "no title"
              Expect.isFalse (json.Contains "pdf_url") "no file"
              Expect.isFalse (json.Contains "author_login") "no author"

          testCase "the receipt names the id, the links, the hash and the record"
          <| fun () ->
              let json = render (receiptJson (record Public))
              Expect.stringContains json "\"url\":\"/studies/abcdefghij\"" "url"
              Expect.stringContains json "\"record\":{" "record" ]
