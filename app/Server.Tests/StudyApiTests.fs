module Marola.Server.Tests.StudyApiTests

open System
open System.IO
open System.Net
open System.Net.Http
open System.Text
open System.Text.Json
open System.Threading.Tasks
open Expecto
open Marola.Server
open Marola.Server.Tests.Harness
open Marola.Server.Tests.PdfTests

let private goodFields =
    [ "title", "Enterococcus in Praia do Leblon, 2025"
      "authors", "Ana Silva | 0000-0002-1825-0097\nBruno Costa"
      "abstract", String.replicate 12 "Sampling of bathing water. "
      "area", "rio"
      "topic", "water-quality"
      "sources", "https://example.org/data"
      "rights", "true"
      "ai_contribution", "none" ]

let private account (site: Site) (id: int64) (login: string) (ageDays: int) : string =
    let created = site.Clock.Now.AddDays(float -ageDays)

    StudyStore.upsertAccount
        site.Config.Db
        site.Clock.Now
        { GithubId = id
          Login = login
          CreatedGithubUtc = StudyStore.utc created }

    match StudyStore.issueKey site.Config.Db site.Clock.Now id with
    | Ok key -> key
    | Error _ -> failwith "no key"

/// A multipart body: the text fields, then the file, with the parts the test adds or replaces.
let private body (fields: (string * string) list) (pdf: byte[] option) : MultipartFormDataContent =
    let m = new MultipartFormDataContent()

    for (k, v) in fields do
        m.Add(new StringContent(v, Encoding.UTF8), k)

    pdf
    |> Option.iter (fun bytes -> m.Add(new ByteArrayContent(bytes), "pdf", "study.pdf"))

    m

let private send (site: Site) (key: string option) (url: string) (content: HttpContent) : Task<HttpResponseMessage> =
    let request = new HttpRequestMessage(HttpMethod.Post, url)

    key
    |> Option.iter (fun k -> request.Headers.Add("Authorization", "Bearer " + k))

    request.Content <- content
    site.Client.SendAsync request

let private submit site key fields pdf =
    send site (Some key) "/api/v1/studies" (body fields (Some pdf))

let private json (response: HttpResponseMessage) : JsonElement =
    JsonDocument.Parse(response.Content.ReadAsStringAsync().Result).RootElement

let private status (r: HttpResponseMessage) = int r.StatusCode

let private errorCodes (r: HttpResponseMessage) : (string * string) list =
    [ for e in (json r).GetProperty("errors").EnumerateArray() ->
          e.GetProperty("field").GetString(), e.GetProperty("code").GetString() ]

let private has (items: (string * string) list) (item: string * string) =
    Expect.contains items item (sprintf "%A" item)

let private studyFiles (site: Site) =
    if Directory.Exists site.Config.Studies then
        Directory.GetFiles(site.Config.Studies, "*", SearchOption.AllDirectories)
    else
        [||]

let private rows (site: Site) =
    StudyStore.listStudies site.Config.Db None None None 50

let private later (site: Site) =
    site.Clock.Advance(TimeSpan.FromMinutes 11.)

let private run (body: Site -> Task) = plainSite body

let tests =
    testList
        "study api"
        [ testTask "a submission is stored and answered with 201, the id, the links, the hash and the record" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          use! r = submit site key goodFields validPdf
                          Expect.equal (status r) 201 (r.Content.ReadAsStringAsync().Result)
                          Expect.equal (header r "Content-Type") (Some "application/json; charset=utf-8") "json"
                          Expect.equal (header r "X-Content-Type-Options") (Some "nosniff") "nosniff"
                          let j = json r
                          let id = j.GetProperty("id").GetString()
                          Expect.isTrue (Marola.Study.validId id) "id shape"
                          Expect.equal (j.GetProperty("sha256").GetString()) (sha validPdf) "hash"

                          Expect.equal
                              (j.GetProperty("received_utc").GetString())
                              "2026-11-11T12:00:00Z"
                              "the server's clock"

                          Expect.equal (j.GetProperty("status").GetString()) "public" "public at once"
                          Expect.equal (j.GetProperty("url").GetString()) ("/studies/" + id) "url"
                          Expect.equal (j.GetProperty("pdf_url").GetString()) ("/studies/" + id + ".pdf") "pdf url"
                          let record = j.GetProperty "record"
                          Expect.equal (record.GetProperty("review").GetString()) "not reviewed" "label"
                          Expect.equal (record.GetProperty("author_login").GetString()) "ana" "author"

                          Expect.equal
                              (File.ReadAllBytes(Path.Combine(site.Config.Studies, sha validPdf + ".pdf")))
                              validPdf
                              "file"

                          Expect.equal (List.length (rows site)) 1 "row"
                      })
          }

          testTask "the PDF route serves the file with the sandbox headers that replace the page CSP" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          use! created = submit site key goodFields validPdf
                          let id = (json created).GetProperty("id").GetString()
                          use! r = site.Client.GetAsync("/studies/" + id + ".pdf")
                          Expect.equal (status r) 200 "200"
                          Expect.equal (header r "Content-Type") (Some "application/pdf") "type"

                          Expect.equal
                              (header r "Content-Disposition")
                              (Some("inline; filename=\"" + id + ".pdf\""))
                              "disposition"

                          Expect.equal (header r "X-Content-Type-Options") (Some "nosniff") "nosniff"

                          Expect.equal
                              (header r "Content-Security-Policy")
                              (Some "sandbox; default-src 'none'")
                              "CSP replaced, not added to"

                          Expect.equal (header r "Cache-Control") (Some "public, max-age=3600") "cache"
                          Expect.equal (r.Content.ReadAsByteArrayAsync().Result) validPdf "bytes"
                      })
          }

          testTask "a dry run answers what it would do and leaves no file, no folder and no row" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          use! r = send site (Some key) "/api/v1/studies?dry_run=1" (body goodFields (Some validPdf))
                          Expect.equal (status r) 200 (r.Content.ReadAsStringAsync().Result)
                          let j = json r
                          Expect.isTrue (j.GetProperty("dry_run").GetBoolean()) "dry_run"
                          Expect.equal (j.GetProperty("sha256").GetString()) (sha validPdf) "hash"
                          Expect.isEmpty (rows site) "no row"
                          Expect.isFalse (Directory.Exists site.Config.Studies) "no folder"
                          // A dry run does not use up the 10 minutes of a real one.
                          use! real = submit site key goodFields validPdf
                          Expect.equal (status real) 201 "a real one follows at once"
                      })
          }

          testTask "a dry run finds the same errors, the duplicate and the 10 minute gap" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          use! first = submit site key goodFields validPdf
                          Expect.equal (status first) 201 "first"

                          use! soon =
                              send
                                  site
                                  (Some key)
                                  "/api/v1/studies?dry_run=1"
                                  (body goodFields (Some(pdfBytes "/A 1" 0)))

                          Expect.equal (status soon) 429 "the gap applies to a dry run"
                          later site
                          use! dup = send site (Some key) "/api/v1/studies?dry_run=1" (body goodFields (Some validPdf))
                          Expect.equal (status dup) 409 "duplicate"

                          use! bad =
                              send
                                  site
                                  (Some key)
                                  "/api/v1/studies?dry_run=1"
                                  (body (List.tail goodFields) (Some validPdf))

                          Expect.equal (status bad) 400 "validation"
                          Expect.equal (List.length (rows site)) 1 "still one row"
                          Expect.equal (studyFiles site |> Array.length) 1 "still one file"
                      })
          }

          testTask "401 without a key, with a wrong key and with a revoked key; 403 for a young account" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          use! none = send site None "/api/v1/studies" (body goodFields (Some validPdf))
                          Expect.equal (status none) 401 "no key"
                          Expect.equal (errorCodes none) [ "request", "unauthorized" ] "code"
                          Expect.isSome (header none "WWW-Authenticate") "challenge"

                          use! wrong =
                              submit
                                  site
                                  (key.Substring(0, 55) + (if key.EndsWith "a" then "b" else "a"))
                                  goodFields
                                  validPdf

                          Expect.equal (status wrong) 401 "wrong"
                          use! junk = submit site "msk_../../etc" goodFields validPdf
                          Expect.equal (status junk) 401 "junk"
                          let id = (StudyStore.listKeys site.Config.Db 1L).Head.Id
                          StudyStore.revokeKey site.Config.Db site.Clock.Now 1L id |> ignore
                          use! revoked = submit site key goodFields validPdf
                          Expect.equal (status revoked) 401 "revoked"
                          let young = account site 2L "novo" 6
                          use! r = submit site young goodFields validPdf
                          Expect.equal (status r) 403 "6 days old"
                          Expect.equal (errorCodes r) [ "request", "account_too_new" ] "code"
                          Expect.isEmpty (rows site) "nothing stored"
                      })
          }

          testTask "400 lists every error at once with codes, and a bad file adds its own" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30

                          let fields =
                              [ "title", "no"
                                "authors", "Ana | 0000-0002-1825-0098"
                                "area", "mars"
                                "rights", "false"
                                "ai_contribution", "drafting" ]

                          use! r = submit site key fields (Text.Encoding.ASCII.GetBytes "not a pdf")
                          Expect.equal (status r) 400 "400"
                          let codes = errorCodes r

                          for expected in
                              [ "title", "too_short"
                                "authors", "bad_orcid"
                                "abstract", "required"
                                "area", "unknown_value"
                                "topic", "required"
                                "rights", "must_be_true"
                                "ai_process", "required"
                                "pdf", "not_pdf" ] do
                              has codes expected

                          use! missing = send site (Some key) "/api/v1/studies" (body goodFields None)
                          Expect.equal (errorCodes missing) [ "pdf", "required" ] "no file"
                          use! js = submit site key goodFields (pdfBytes "/S /JavaScript" 0)
                          Expect.equal (errorCodes js) [ "pdf", "active_content" ] "active content"
                          use! cut = submit site key goodFields validPdf[.. validPdf.Length - 25]
                          Expect.equal (errorCodes cut) [ "pdf", "truncated" ] "truncated"
                          Expect.isEmpty (studyFiles site) "no file is left"
                      })
          }

          testTask "the same file from the same account is a 409 that names the old id; another account may send it" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          let other = account site 2L "bia" 30
                          use! first = submit site key goodFields validPdf
                          let id = (json first).GetProperty("id").GetString()
                          later site
                          use! dup = submit site key goodFields validPdf
                          Expect.equal (status dup) 409 "409"
                          Expect.equal ((json dup).GetProperty("id").GetString()) id "old id"
                          use! theirs = submit site other goodFields validPdf
                          Expect.equal (status theirs) 201 "another account"
                          Expect.equal (studyFiles site |> Array.length) 1 "one file for one hash"
                      })
          }

          testTask "413 for a file over 20 MB (by the stream) and for a request over 21 MB (by its length)" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          use! big = submit site key goodFields (Array.zeroCreate (20 * 1024 * 1024 + 1))
                          Expect.equal (status big) 413 "file"
                          Expect.equal (errorCodes big) [ "pdf", "too_large" ] "code"
                          use! huge = submit site key goodFields (Array.zeroCreate (22 * 1024 * 1024))
                          Expect.equal (status huge) 413 "request"
                          Expect.isEmpty (studyFiles site) "no file is left"
                      })
          }

          testTask "415 for a JSON body and a form body" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30

                          use! j =
                              send
                                  site
                                  (Some key)
                                  "/api/v1/studies"
                                  (new StringContent("{}", Encoding.UTF8, "application/json"))

                          Expect.equal (status j) 415 "json"
                          use! f = send site (Some key) "/api/v1/studies" (form goodFields)
                          Expect.equal (status f) 415 "form"
                      })
          }

          testTask "429: one real submission every 10 minutes, and the 11th in a day" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          use! first = submit site key goodFields (pdfBytes "/N 0" 0)
                          Expect.equal (status first) 201 "first"
                          use! soon = submit site key goodFields (pdfBytes "/N 1" 0)
                          Expect.equal (status soon) 429 "too soon"
                          Expect.equal (errorCodes soon) [ "request", "too_soon" ] "code"
                          Expect.equal (header soon "Retry-After") (Some "600") "Retry-After"

                          for i in 2..10 do
                              later site
                              use! r = submit site key goodFields (pdfBytes ("/N " + string i) 0)
                              Expect.equal (status r) 201 (sprintf "submission %d" i)

                          later site
                          use! eleventh = submit site key goodFields (pdfBytes "/N 11" 0)
                          Expect.equal (status eleventh) 429 "the 11th in a day"
                          Expect.equal (errorCodes eleventh) [ "request", "daily_limit" ] "code"
                          Expect.equal (List.length (rows site)) 10 "ten stored"
                          // A day after the first one, the window has moved.
                          site.Clock.Advance(TimeSpan.FromDays 1.)
                          use! next = submit site key goodFields (pdfBytes "/N 12" 0)
                          Expect.equal (status next) 201 "a day later"
                      })
          }

          testTask "30 requests a minute per key: dry runs count a third, so 90 pass and the 91st is a 429" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30

                          for i in 1..90 do
                              use! r = send site (Some key) "/api/v1/studies?dry_run=1" (body [] None)
                              Expect.equal (status r) 400 (sprintf "request %d reaches validation" i)

                          use! over = send site (Some key) "/api/v1/studies?dry_run=1" (body [] None)
                          Expect.equal (status over) 429 "91st"
                          Expect.equal (errorCodes over) [ "request", "rate_limited" ] "code"
                          site.Clock.Advance(TimeSpan.FromSeconds 61.)
                          use! again = send site (Some key) "/api/v1/studies?dry_run=1" (body [] None)
                          Expect.equal (status again) 400 "the window moved"
                      })
          }

          testTask "507 when the store is full: the quota refuses a new file and a dry run says so" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          let big = pdfBytes "" 1_100_000
                          use! dry = send site (Some key) "/api/v1/studies?dry_run=1" (body goodFields (Some big))
                          Expect.equal (status dry) 507 "dry run"
                          use! r = submit site key goodFields big
                          Expect.equal (status r) 507 "507"
                          Expect.equal (errorCodes r) [ "pdf", "quota_exceeded" ] "code"
                          Expect.isEmpty (studyFiles site) "no file is left"
                          Expect.isEmpty (rows site) "no row"
                      })
          }

          testTask "multipart limits: duplicate names, non-UTF-8, unknown fields, too many parts, oversized fields" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30

                          use! dup =
                              send
                                  site
                                  (Some key)
                                  "/api/v1/studies?dry_run=1"
                                  (body (goodFields @ [ "title", "again" ]) (Some validPdf))

                          Expect.contains (errorCodes dup) ("request", "duplicate_field") "duplicate"

                          let m = body (List.filter (fun (k, _) -> k <> "title") goodFields) (Some validPdf)
                          m.Add(new ByteArrayContent([| 0xffuy; 0xfeuy; 0x41uy |]), "title")
                          use! utf = send site (Some key) "/api/v1/studies?dry_run=1" m
                          Expect.contains (errorCodes utf) ("title", "invalid_utf8") "utf-8"

                          use! unknown =
                              send
                                  site
                                  (Some key)
                                  "/api/v1/studies?dry_run=1"
                                  (body (goodFields @ [ "evil", "x" ]) (Some validPdf))

                          Expect.contains (errorCodes unknown) ("request", "unknown_field") "unknown"

                          let many = [ for i in 1..25 -> sprintf "f%d" i, "x" ]
                          use! parts = send site (Some key) "/api/v1/studies?dry_run=1" (body many (Some validPdf))
                          Expect.contains (errorCodes parts) ("request", "too_many_parts") "parts"

                          let longTitle =
                              goodFields
                              |> List.map (fun (k, v) -> if k = "title" then k, String.replicate 21_000 "a" else k, v)

                          use! long = send site (Some key) "/api/v1/studies?dry_run=1" (body longTitle (Some validPdf))
                          Expect.contains (errorCodes long) ("title", "too_long") "field size"

                          use! noBoundary =
                              send
                                  site
                                  (Some key)
                                  "/api/v1/studies"
                                  (new StringContent("x", Encoding.UTF8, "multipart/form-data"))

                          Expect.equal (status noBoundary) 400 "no boundary"
                      })
          }

          testTask "control characters are stripped from stored text" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30

                          let fields =
                              goodFields
                              |> List.map (fun (k, v) ->
                                  if k = "title" then
                                      k, "Water\u0001 at\u001b Leblon"
                                  else
                                      k, v)

                          use! r = submit site key fields validPdf
                          Expect.equal (status r) 201 "201"

                          Expect.equal
                              ((json r).GetProperty("record").GetProperty("title").GetString())
                              "Water at Leblon"
                              "stripped"
                      })
          }

          testTask "GET: the record, the list with filters and paging, 404 for bad and unknown ids" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          let ids = ResizeArray<string>()

                          for i in 0..2 do
                              let fields =
                                  goodFields
                                  |> List.map (fun (k, v) -> if k = "area" && i = 1 then k, "floripa" else k, v)

                              use! r = submit site key fields (pdfBytes ("/N " + string i) 0)
                              ids.Add((json r).GetProperty("id").GetString())
                              later site

                          use! one = site.Client.GetAsync("/api/v1/studies/" + ids[0])
                          Expect.equal (status one) 200 "get"
                          Expect.equal (header one "Content-Type") (Some "application/json; charset=utf-8") "json"
                          Expect.equal ((json one).GetProperty("id").GetString()) ids[0] "id"
                          use! all = site.Client.GetAsync "/api/v1/studies"

                          let listed =
                              [ for s in (json all).GetProperty("studies").EnumerateArray() ->
                                    s.GetProperty("id").GetString() ]

                          Expect.equal listed [ ids[2]; ids[1]; ids[0] ] "newest first"
                          use! rio = site.Client.GetAsync "/api/v1/studies?area=rio"

                          Expect.equal
                              ([ for s in (json rio).GetProperty("studies").EnumerateArray() ->
                                     s.GetProperty("id").GetString() ])
                              [ ids[2]; ids[0] ]
                              "area"

                          use! page = site.Client.GetAsync("/api/v1/studies?limit=1&before=" + ids[2])

                          Expect.equal
                              ([ for s in (json page).GetProperty("studies").EnumerateArray() ->
                                     s.GetProperty("id").GetString() ])
                              [ ids[1] ]
                              "before"

                          Expect.equal ((json page).GetProperty("next_before").GetString()) ids[1] "cursor"
                          use! badLimit = site.Client.GetAsync "/api/v1/studies?limit=51"
                          Expect.equal (status badLimit) 400 "limit"
                          use! badArea = site.Client.GetAsync "/api/v1/studies?area=mars&before=x"
                          Expect.equal (errorCodes badArea |> List.length) 2 "both reported"
                          use! unknown = site.Client.GetAsync "/api/v1/studies/aaaaaaaaaa"
                          Expect.equal (status unknown) 404 "unknown"
                          use! traversal = site.Client.GetAsync "/api/v1/studies/..%2f..%2fsecret"
                          Expect.equal (status traversal) 404 "bad id"
                          use! pdfBad = site.Client.GetAsync "/studies/..%2f..%2fsecret.pdf"
                          Expect.equal (status pdfBad) 404 "pdf, bad id"
                          use! pdfUnknown = site.Client.GetAsync "/studies/aaaaaaaaaa.pdf"
                          Expect.equal (status pdfUnknown) 404 "pdf, unknown"
                      })
          }

          testTask "a hidden study is a tombstone: no text, no file link, no file, and it leaves the list" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          use! created = submit site key goodFields validPdf
                          let id = (json created).GetProperty("id").GetString()
                          Expect.isTrue (StudyStore.hide site.Config.Db site.Clock.Now id "wrong unit") "hide"
                          use! one = site.Client.GetAsync("/api/v1/studies/" + id)
                          Expect.equal (status one) 200 "the tombstone is public"
                          let text = one.Content.ReadAsStringAsync().Result
                          Expect.stringContains text "\"status\":\"hidden\"" "status"
                          Expect.stringContains text "wrong unit" "reason"
                          Expect.stringContains text (sha validPdf) "hash"
                          Expect.stringContains text "2026-11-11T12:00:00Z" "date"
                          Expect.isFalse (text.Contains "Enterococcus") "no title"
                          Expect.isFalse (text.Contains "pdf_url") "no link"
                          use! file = site.Client.GetAsync("/studies/" + id + ".pdf")
                          Expect.equal (status file) 404 "no file"
                          Expect.isFalse (file.Content.ReadAsStringAsync().Result.Contains "%PDF") "no bytes"
                          use! all = site.Client.GetAsync "/api/v1/studies"
                          Expect.equal ((json all).GetProperty("studies").GetArrayLength()) 0 "not listed"
                      })
          }

          testTask "skill.md is plain text, names the endpoint, the dry run, the levels and holds no key" {
              do!
                  run (fun site ->
                      task {
                          use! r = site.Client.GetAsync "/api/v1/skill.md"
                          Expect.equal (status r) 200 "200"
                          Expect.equal (header r "Content-Type") (Some "text/plain; charset=utf-8") "type"
                          let text = r.Content.ReadAsStringAsync().Result

                          for needle in
                              [ "/api/v1/studies"
                                "dry_run=1"
                                "curl"
                                "autonomous"
                                "language-editing"
                                "%PDF-"
                                "%%EOF"
                                "429"
                                "507" ] do
                              Expect.stringContains text needle needle

                          Expect.isFalse (Text.RegularExpressions.Regex.IsMatch(text, "msk_[a-z2-7]{52}")) "no key"
                      })
          }

          testTask "the log has the study id and the account id, and nothing the author wrote" {
              do!
                  run (fun site ->
                      task {
                          let key = account site 1L "ana" 30
                          use! r = submit site key goodFields validPdf
                          let id = (json r).GetProperty("id").GetString()
                          let log = String.concat "\n" site.Capture.Lines
                          Expect.stringContains log id "the id"

                          for secret in [ "Enterococcus"; "Sampling"; "study.pdf"; "Ana Silva"; key; "127.0.0.1" ] do
                              Expect.isFalse (log.Contains secret) ("not in the log: " + secret)
                      })
          } ]
