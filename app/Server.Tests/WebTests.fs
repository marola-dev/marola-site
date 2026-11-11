module Marola.Server.Tests.WebTests

open System
open System.IO
open System.Net
open System.Net.Http
open System.Text
open System.Text.RegularExpressions
open System.Threading.Tasks
open System.Xml.Linq
open Expecto
open Marola
open Marola.Server
open Marola.Server.Tests.Harness
open Marola.Server.Tests.PdfTests

let private same = "http://localhost"

let private good =
    [ "title", "Enterococcus in Praia do Leblon, 2025"
      "authors", "Ana Silva | 0000-0002-1825-0097\nBruno Costa"
      "abstract", String.replicate 12 "Sampling of bathing water. "
      "area", "rio"
      "topic", "water-quality"
      "sources", "https://example.org/data"
      "rights", "true"
      "ai_contribution", "none" ]

/// An account of 30 days at GitHub, with a live session: the cookie a browser would hold and its CSRF token.
let private loggedIn (site: Site) (id: int64) (login: string) : string * string =
    StudyStore.upsertAccount
        site.Config.Db
        site.Clock.Now
        { GithubId = id
          Login = login
          CreatedGithubUtc = StudyStore.utc (site.Clock.Now.AddDays -30.) }

    let token = StudyStore.createSession site.Config.Db site.Clock.Now id

    let hash =
        StudyStore.getSession site.Config.Db site.Clock.Now token |> Option.get |> snd

    "__Host-msess=" + token, Session.csrfToken (Session.loadKey site.Config.Db) hash

let private send
    (site: Site)
    (meth: HttpMethod)
    (url: string)
    (cookie: string option)
    (origin: string option)
    (content: HttpContent option)
    =
    let request = new HttpRequestMessage(meth, url)
    cookie |> Option.iter (fun c -> request.Headers.Add("Cookie", c))
    origin |> Option.iter (fun o -> request.Headers.Add("Origin", o))
    content |> Option.iter (fun c -> request.Content <- c)
    site.Client.SendAsync request

let private getPage (site: Site) (url: string) (cookie: string option) =
    send site HttpMethod.Get url cookie None None

let private multipart (csrf: string option) (fields: (string * string) list) (pdf: byte[] option) =
    let m = new MultipartFormDataContent()
    csrf |> Option.iter (fun c -> m.Add(new StringContent(c), "csrf"))

    for (k, v) in fields do
        m.Add(new StringContent(v, Encoding.UTF8), k)

    pdf |> Option.iter (fun b -> m.Add(new ByteArrayContent(b), "pdf", "study.pdf"))
    m :> HttpContent

let private text (r: HttpResponseMessage) = r.Content.ReadAsStringAsync().Result
let private status (r: HttpResponseMessage) = int r.StatusCode

let private files (site: Site) =
    if Directory.Exists site.Config.Studies then
        Directory.GetFiles(site.Config.Studies, "*", SearchOption.AllDirectories)
    else
        [||]

let private idFrom (r: HttpResponseMessage) =
    (string r.Headers.Location).Split('/') |> Array.last

/// Publishes one study through the form and returns its id.
let private publish
    (site: Site)
    (cookie: string)
    (csrf: string)
    (fields: (string * string) list)
    (pdf: byte[])
    : Task<string> =
    task {
        use! r =
            send
                site
                HttpMethod.Post
                "/submit"
                (Some cookie)
                (Some same)
                (Some(multipart (Some csrf) fields (Some pdf)))

        Expect.equal (status r) 303 (text r)
        return idFrom r
    }

let private run body = plainSite body

let private hrefs (html: string) =
    [ for m in Regex.Matches(html, "href=\"([^\"]*)\"") -> m.Groups[1].Value ]

let tests =
    testList
        "web"
        [ test "every error code has a message in both languages, and the API's codes are all covered" {
              for (code, pt, en) in Messages.table do
                  Expect.isNotEmpty pt (code + " pt-BR")
                  Expect.isNotEmpty en (code + " en")
                  Expect.notEqual pt en (code + " is translated")

              let errors = StudyApi.skill.Substring(StudyApi.skill.IndexOf "## Errors")

              let listed =
                  [ for m in Regex.Matches(errors, "`([a-z_]+)`") do
                        if m.Groups[1].Value <> "id" then
                            m.Groups[1].Value ]

              Expect.isNonEmpty listed "the guide lists codes"

              for code in
                  listed
                  @ [ "too_large"
                      "duplicate"
                      "quota_exceeded"
                      "account_too_new"
                      "rate_limited"
                      "unauthorized"
                      "too_soon"
                      "daily_limit"
                      "csrf" ] do
                  Expect.contains Messages.codes code ("a message for " + code)
          }
          testTask
              "a visitor sees the login button; a logged-in one sees the form with a token, both with the headers and no script" {
              do!
                  run (fun site ->
                      task {
                          use! out = getPage site "/submit" None
                          let html = text out
                          Expect.equal (status out) 200 "ok"
                          Expect.stringContains html "/auth/github/login" "login link"
                          Expect.isFalse (html.Contains "<form method=\"POST\" action=\"/submit\"") "no form"

                          Expect.stringContains
                              (header out "Cache-Control" |> Option.defaultValue "")
                              "no-store"
                              "no-store"

                          Expect.isSome (header out "Content-Security-Policy") "CSP"
                          Expect.stringContains html "/api/v1/skill.md" "for agents"
                          let cookie, csrf = loggedIn site 1L "ana"
                          use! inn = getPage site "/en/submit" (Some cookie)
                          let page = text inn
                          Expect.stringContains page "action=\"/en/submit\"" "form"
                          Expect.stringContains page ("name=\"csrf\" value=\"" + csrf + "\"") "token"
                          Expect.isFalse (page.Contains "<script") "no script"
                          Expect.isFalse (page.Contains "style=") "no inline style"
                      })
          }
          testTask "the form publishes through the intake: the study page shows the file's hash, and the file is stored" {
              do!
                  run (fun site ->
                      task {
                          let cookie, csrf = loggedIn site 1L "ana"
                          let id = publish site cookie csrf good validPdf |> fun t -> t.Result
                          Expect.equal (files site |> Array.length) 1 "one file"
                          use! page = getPage site ("/studies/" + id) None
                          let html = text page
                          Expect.stringContains html (sha validPdf) "the full hash"
                          Expect.stringContains html "https://orcid.org/0000-0002-1825-0097" "orcid"
                          Expect.stringContains html "/report/" "report link"

                          Expect.stringContains
                              (header page "Cache-Control" |> Option.defaultValue "")
                              "max-age=60"
                              "cache"

                          use! pdf = getPage site ("/studies/" + id + ".pdf") None
                          Expect.equal (status pdf) 200 "pdf"
                          // The same limits as the API: a second post at once is too soon.
                          use! again =
                              send
                                  site
                                  HttpMethod.Post
                                  "/submit"
                                  (Some cookie)
                                  (Some same)
                                  (Some(multipart (Some csrf) good (Some(pdfBytes "" 5))))

                          Expect.equal (status again) 429 "one per 10 minutes"
                          Expect.stringContains (text again) "um envio por conta a cada 10 minutos" "message in pt-BR"
                      })
          }
          testTask "a post without the token, with a wrong token or from another site is 403 and stores nothing" {
              do!
                  run (fun site ->
                      task {
                          let cookie, csrf = loggedIn site 1L "ana"

                          for csrfField, origin in [ None, same; Some "0000", same; Some csrf, "https://evil.example" ] do
                              use! r =
                                  send
                                      site
                                      HttpMethod.Post
                                      "/submit"
                                      (Some cookie)
                                      (Some origin)
                                      (Some(multipart csrfField good (Some validPdf)))

                              Expect.equal (status r) 403 "403"

                          Expect.isEmpty (files site) "no file"
                          Expect.isEmpty (StudyStore.listStudies site.Config.Db None None None 10) "no study"

                          use! outCookie =
                              send
                                  site
                                  HttpMethod.Post
                                  "/submit"
                                  None
                                  (Some same)
                                  (Some(multipart (Some csrf) good (Some validPdf)))

                          Expect.equal (status outCookie) 303 "no session: to login"
                          Expect.stringContains (string outCookie.Headers.Location) "/auth/github/login" "login"
                      })
          }
          testTask "errors come back all at once, next to the fields, in the page language" {
              do!
                  run (fun site ->
                      task {
                          let cookie, csrf = loggedIn site 1L "ana"

                          let bad =
                              [ "title", "no"
                                "authors", "Ana | 0000-0002-1825-0098"
                                "area", "mars"
                                "ai_contribution", "drafting" ]

                          use! pt =
                              send
                                  site
                                  HttpMethod.Post
                                  "/submit"
                                  (Some cookie)
                                  (Some same)
                                  (Some(multipart (Some csrf) bad (Some(Encoding.ASCII.GetBytes "x"))))

                          Expect.equal (status pt) 400 "400"
                          let html = text pt
                          Expect.stringContains html "escreva pelo menos 5 caracteres" "title"
                          Expect.stringContains html "o ORCID iD não é válido" "orcid"
                          Expect.stringContains html "preencha este campo" "required"
                          Expect.stringContains html "este arquivo não é um PDF" "pdf"
                          Expect.stringContains html "value=\"no\"" "the typed value stays"

                          use! en =
                              send
                                  site
                                  HttpMethod.Post
                                  "/en/submit"
                                  (Some cookie)
                                  (Some same)
                                  (Some(multipart (Some csrf) bad (Some(Encoding.ASCII.GetBytes "x"))))

                          Expect.stringContains (text en) "write at least 5 characters" "english"
                          Expect.isEmpty (files site) "nothing stored"
                      })
          }
          testTask "study text is escaped in the page, the list and the feed; the feed is well-formed Atom" {
              do!
                  run (fun site ->
                      task {
                          let cookie, csrf = loggedIn site 1L "ana"
                          let evil = "<script>alert(1)</script> \"onmouseover=\"alert(2)"

                          let fields =
                              [ "title", "T " + evil
                                "authors", "Ana " + evil
                                "abstract", String.replicate 3 (evil + " ") + String.replicate 12 "padding text. "
                                "area", "rio"
                                "topic", "water-quality"
                                "sources", "https://example.org/a?x=%22onmouseover=1&y=<b>"
                                "repository", "https://example.org/r?q=\"onmouseover=3"
                                "rights", "true"
                                "ai_contribution", "drafting"
                                "ai_models", evil
                                "ai_process", evil ]

                          use! r =
                              send
                                  site
                                  HttpMethod.Post
                                  "/submit"
                                  (Some cookie)
                                  (Some same)
                                  (Some(multipart (Some csrf) fields (Some validPdf)))

                          let id = idFrom r

                          for url in [ "/studies/" + id; "/en/studies/" + id; "/studies"; "/studies.atom" ] do
                              use! page = getPage site url None
                              let html = text page
                              Expect.isFalse (html.Contains "<script>alert") (url + ": no raw script")

                              Expect.isFalse
                                  (Regex.IsMatch(html, "<[^>]*(\\s|\")onmouseover="))
                                  (url + ": no attribute break out")

                              Expect.isFalse (html.Contains "<b>") (url + ": no raw tag")

                          use! feed = getPage site "/studies.atom" None
                          let doc = XDocument.Parse(text feed)
                          Expect.equal doc.Root.Name.LocalName "feed" "Atom feed"

                          Expect.equal
                              (header feed "Content-Type" |> Option.map (fun v -> v.Split(';').[0]))
                              (Some "application/atom+xml")
                              "type"

                          Expect.equal
                              (doc.Root.Elements()
                               |> Seq.filter (fun e -> e.Name.LocalName = "entry")
                               |> Seq.length)
                              1
                              "one entry"
                      })
          }
          testTask
              "the list hides hidden studies, filters and pages; a tombstone has no text, noindex, and its file is gone" {
              do!
                  run (fun site ->
                      task {
                          let cookie, csrf = loggedIn site 1L "ana"
                          let id = publish site cookie csrf good validPdf |> fun t -> t.Result
                          use! list = getPage site "/studies" None
                          Expect.stringContains (text list) id "listed"
                          use! other = getPage site "/studies?area=salvador" None
                          Expect.isFalse ((text other).Contains id) "filtered out"

                          use! account = getPage site "/account" (Some cookie)
                          Expect.stringContains (text account) ("/account/withdraw/" + id) "withdraw button"
                          Expect.stringContains (text account) "noindex" "account is noindex"

                          use! no =
                              send
                                  site
                                  HttpMethod.Post
                                  ("/account/withdraw/" + id)
                                  (Some cookie)
                                  (Some same)
                                  (Some(form [ "csrf", "bad" ]))

                          Expect.equal (status no) 403 "no token"

                          use! yes =
                              send
                                  site
                                  HttpMethod.Post
                                  ("/account/withdraw/" + id)
                                  (Some cookie)
                                  (Some same)
                                  (Some(form [ "csrf", csrf ]))

                          Expect.equal (status yes) 303 "withdrawn"

                          use! tomb = getPage site ("/studies/" + id) None
                          let html = text tomb
                          Expect.equal (status tomb) 200 "tombstone"
                          Expect.stringContains html "withdrawn by the author" "reason"
                          Expect.stringContains html (sha validPdf) "hash"
                          Expect.stringContains html "name=\"robots\" content=\"noindex\"" "noindex"
                          Expect.isFalse (html.Contains "Enterococcus") "no text"
                          Expect.isFalse (html.Contains(id + ".pdf")) "no file link"
                          use! pdf = getPage site ("/studies/" + id + ".pdf") None
                          Expect.equal (status pdf) 404 "no file"
                          use! gone = getPage site "/studies" None
                          Expect.isFalse ((text gone).Contains id) "not listed"
                          use! unknown = getPage site "/studies/aaaaaaaaaa" None
                          Expect.equal (status unknown) 404 "unknown id"
                      })
          }
          testTask "the account page needs a session; a key is shown once; revoke and logout work" {
              do!
                  run (fun site ->
                      task {
                          use! anon = getPage site "/account" None
                          Expect.equal (status anon) 303 "login"
                          let cookie, csrf = loggedIn site 1L "ana"

                          use! made =
                              send
                                  site
                                  HttpMethod.Post
                                  "/account/keys"
                                  (Some cookie)
                                  (Some same)
                                  (Some(form [ "csrf", csrf ]))

                          let html = text made
                          let key = Regex.Match(html, "msk_[a-z2-7]{52}").Value
                          Expect.isNotEmpty key "the key is on the answer"

                          Expect.stringContains
                              (header made "Cache-Control" |> Option.defaultValue "")
                              "no-store"
                              "no-store"

                          Expect.isSome (StudyStore.verifyKey site.Config.Db key) "the key works"
                          use! again = getPage site "/account" (Some cookie)
                          Expect.isFalse ((text again).Contains key) "not shown again"
                          let keyId = (StudyStore.listKeys site.Config.Db 1L).Head.Id

                          use! revoked =
                              send
                                  site
                                  HttpMethod.Post
                                  (sprintf "/account/keys/%d/revoke" keyId)
                                  (Some cookie)
                                  (Some same)
                                  (Some(form [ "csrf", csrf ]))

                          Expect.equal (status revoked) 303 "revoked"
                          Expect.isNone (StudyStore.verifyKey site.Config.Db key) "the key is dead"

                          use! out =
                              send
                                  site
                                  HttpMethod.Post
                                  "/logout"
                                  (Some cookie)
                                  (Some same)
                                  (Some(form [ "csrf", csrf ]))

                          Expect.equal (status out) 303 "logout"
                          use! after = getPage site "/account" (Some cookie)
                          Expect.equal (status after) 303 "the session is gone"
                      })
          }
          testTask
              "a report stores the reason and the time and no address; the honeypot stores nothing; no login needed" {
              do!
                  run (fun site ->
                      task {
                          let cookie, csrf = loggedIn site 1L "ana"
                          let id = publish site cookie csrf good validPdf |> fun t -> t.Result
                          use! page = getPage site ("/report/" + id) None
                          Expect.equal (status page) 200 "form"
                          Expect.isFalse ((text page).Contains "type=\"email\"") "no email field"

                          use! sent =
                              send
                                  site
                                  HttpMethod.Post
                                  ("/report/" + id)
                                  None
                                  (Some same)
                                  (Some(form [ "reason", "wrong"; "details", "the numbers differ"; "website", "" ]))

                          Expect.equal (status sent) 200 "thanks"

                          use! bot =
                              send
                                  site
                                  HttpMethod.Post
                                  ("/report/" + id)
                                  None
                                  (Some same)
                                  (Some(form [ "reason", "spam"; "website", "x" ]))

                          Expect.equal (status bot) 200 "thanks to a bot too"
                          Expect.equal (StudyStore.countReports site.Config.Db id) 1L "only the real one"

                          use! bad =
                              send
                                  site
                                  HttpMethod.Post
                                  ("/report/" + id)
                                  None
                                  (Some same)
                                  (Some(form [ "reason", "nope" ]))

                          Expect.equal (status bad) 400 "bad reason"
                          use! missing = getPage site "/report/aaaaaaaaaa" None
                          Expect.equal (status missing) 404 "unknown study"

                          use! foreign =
                              send
                                  site
                                  HttpMethod.Post
                                  ("/report/" + id)
                                  None
                                  (Some "https://evil.example")
                                  (Some(form [ "reason", "spam" ]))

                          Expect.equal (status foreign) 403 "other site"

                          Expect.isFalse
                              ((String.concat "\n" site.Capture.Lines).Contains "127.0.0.1")
                              "no address in the log"
                      })
          }
          testTask
              "every page has one h1, no script, no inline style; public pages pair their languages; private ones are noindex" {
              do!
                  run (fun site ->
                      task {
                          let cookie, csrf = loggedIn site 1L "ana"
                          let id = publish site cookie csrf good validPdf |> fun t -> t.Result

                          for path, canonical in
                              [ "/submit", true
                                "/studies", true
                                "/studies/" + id, true
                                "/account", false
                                "/report/" + id, false ] do
                              for prefix in [ ""; "/en" ] do
                                  use! r = getPage site (prefix + path) (Some cookie)
                                  let html = text r
                                  let where = prefix + path
                                  Expect.equal (Regex.Matches(html, "<h1").Count) 1 (where + ": one h1")
                                  Expect.isFalse (html.Contains "<script") (where + ": no script")
                                  Expect.isFalse (html.Contains " style=") (where + ": no inline style")

                                  Expect.stringContains
                                      html
                                      (sprintf "<html lang=\"%s\">" (if prefix = "" then "pt-BR" else "en"))
                                      where

                                  if canonical then
                                      Expect.stringContains
                                          html
                                          ("rel=\"canonical\" href=\"https://marola.dev" + prefix + path + "\"")
                                          (where + ": canonical")

                                      Expect.stringContains
                                          html
                                          ("hreflang=\"pt-BR\" href=\"https://marola.dev" + path + "\"")
                                          (where + ": pt")

                                      Expect.stringContains
                                          html
                                          ("hreflang=\"en\" href=\"https://marola.dev/en" + path + "\"")
                                          (where + ": en")
                                  else
                                      Expect.stringContains html "content=\"noindex\"" (where + ": noindex")

                                  Expect.contains (hrefs html) (prefix + "/studies") (where + ": nav")
                                  Expect.contains (hrefs html) (prefix + "/submit") (where + ": footer")
                      })
          }
          testTask "a board reason is escaped on the tombstone page and in the API" {
              do!
                  run (fun site ->
                      task {
                          let cookie, csrf = loggedIn site 1L "ana"
                          let id = publish site cookie csrf good validPdf |> fun t -> t.Result
                          let hostile = "<script>alert(1)</script> \"onmouseover=x & <b>"
                          Expect.isTrue (StudyStore.hide site.Config.Db site.Clock.Now id hostile) "hide"

                          for path in [ "/studies/" + id; "/en/studies/" + id ] do
                              use! page = getPage site path None
                              let html = text page
                              Expect.isFalse (html.Contains "<script>alert") (path + ": no raw script")

                              Expect.stringContains
                                  html
                                  "&amp; &lt;b&gt;"
                                  (path + ": the ampersand and the tag are escaped")

                              Expect.stringContains html "&lt;script&gt;alert(1)&lt;/script&gt;" (path + ": escaped")

                          use! api = getPage site ("/api/v1/studies/" + id) None
                          let json = text api
                          Expect.isFalse (json.Contains "<script>") "the JSON escapes <"
                          Expect.stringContains json "\\u003cscript\\u003e" "escaped in JSON"
                      })
          }
          testTask "deleting the account needs the typed login, hides the studies, detaches them and logs out" {
              do!
                  run (fun site ->
                      task {
                          let cookie, csrf = loggedIn site 1L "Ana"
                          let id = publish site cookie csrf good validPdf |> fun t -> t.Result

                          let key =
                              StudyStore.issueKey site.Config.Db site.Clock.Now 1L
                              |> Result.toOption
                              |> Option.get

                          let post (fields: (string * string) list) =
                              send site HttpMethod.Post "/account/delete" (Some cookie) (Some same) (Some(form fields))

                          use! page = getPage site "/account" (Some cookie)
                          Expect.stringContains (text page) "/account/delete" "the form is there"

                          use! noToken = post [ "confirm", "Ana"; "csrf", "bad" ]
                          Expect.equal (status noToken) 403 "no token"
                          use! wrong = post [ "confirm", "someone"; "csrf", csrf ]
                          Expect.equal (status wrong) 400 "the login must match"
                          Expect.isSome (StudyStore.getAccount site.Config.Db 1L) "nothing deleted"
                          Expect.equal (StudyStore.getStudy site.Config.Db id).Value.Status Study.Public "still public"

                          use! yes = post [ "confirm", " ana "; "csrf", csrf ]
                          Expect.equal (status yes) 303 "deleted"
                          Expect.stringContains (string yes.Headers) "msess=;" "the session cookie is cleared"

                          Expect.isNone (StudyStore.getAccount site.Config.Db 1L) "account row gone"
                          Expect.isNone (StudyStore.verifyKey site.Config.Db key) "key gone"
                          use! after = getPage site "/account" (Some cookie)
                          Expect.equal (status after) 303 "the session is gone"

                          let study = (StudyStore.getStudy site.Config.Db id).Value
                          Expect.equal study.Status Study.Hidden "hidden"
                          Expect.equal study.HiddenReason (Some "account deleted by the author") "reason"
                          Expect.equal study.AuthorLogin "deleted" "login scrubbed"
                          Expect.isLessThan study.AuthorGithubId 0L "detached from every GitHub id"
                          Expect.equal (files site |> Array.length) 1 "the file stays"

                          use! tomb = getPage site ("/studies/" + id) None
                          Expect.stringContains (text tomb) "account deleted by the author" "tombstone"
                          use! pdf = getPage site ("/studies/" + id + ".pdf") None
                          Expect.equal (status pdf) 404 "the file is not served"

                          // The same GitHub id logs in again: a fresh account, with none of the old studies.
                          let cookie2, csrf2 = loggedIn site 1L "Ana"
                          Expect.isEmpty (StudyStore.listByAuthor site.Config.Db 1L) "no old study on the new account"
                          Expect.isEmpty (StudyStore.listKeys site.Config.Db 1L) "no old key"
                          use! fresh = getPage site "/account" (Some cookie2)
                          Expect.isFalse ((text fresh).Contains id) "the account page lists nothing old"
                          Expect.isFalse (StudyStore.unhide site.Config.Db id) "the old study cannot come back"

                          // The same bytes again are a new study, not the old one: the old row has another author.
                          let again = publish site cookie2 csrf2 good validPdf |> fun t -> t.Result
                          Expect.notEqual again id "a new study"
                      })
          } ]
