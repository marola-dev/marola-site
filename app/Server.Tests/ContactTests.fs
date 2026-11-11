module Marola.Server.Tests.ContactTests

open System
open System.IO
open System.Net.Http
open Expecto
open Marola.Server
open Marola.Server.Tests.Harness

let private same = Some "http://localhost"

let private stored (site: Site) = Store.list site.Config.Db

let private config (db: string) =
    { Port = 0
      Static = ""
      Data = ""
      Db = db }

let private tempDb () =
    Path.Combine(Path.GetTempPath(), "marola-db-" + Guid.NewGuid().ToString "N", "marola.db")

let private cleanup (db: string) =
    Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools()
    Directory.Delete(Path.GetDirectoryName db, true)

let private run (db: string) (args: string list) =
    let out = new StringWriter()
    let err = new StringWriter()
    let code = Inbox.run (config db) args out err
    code, out.ToString(), err.ToString()

let tests =
    testList
        "contact"
        [ testTask "a good post is stored, trimmed, and answered with a redirect" {
              do!
                  plainSite (fun site ->
                      task {
                          use! response =
                              post
                                  site
                                  ""
                                  same
                                  [ "email", "  ana@example.org "
                                    "message", "  Olá, a água da Joaquina está boa?  "
                                    "website", ""
                                    "name", "Ana" ]

                          Expect.equal (int response.StatusCode) 303 "see other"
                          Expect.equal (header response "Location") (Some "/contact?sent=1") "back to the form"
                          Expect.isSome (header response "Content-Security-Policy") "headers"

                          match stored site with
                          | [ m ] ->
                              Expect.equal m.Email "ana@example.org" "email"
                              Expect.equal m.Body "Olá, a água da Joaquina está boa?" "body"
                              Expect.equal m.Id 1L "id"
                              Expect.stringEnds m.CreatedUtc "Z" "UTC"
                          | other -> failtestf "expected one message, got %d" other.Length
                      })
          }

          testTask "CSRF: the Origin, or failing it the Referer, must be this site" {
              do!
                  plainSite (fun site ->
                      task {
                          for (what, origin) in
                              [ "no Origin", None
                                "another site", Some "https://evil.example"
                                "the null origin", Some "null"
                                "same host, another port", Some "http://localhost:81"
                                "garbage", Some "localhost" ] do
                              use! response = post site "" origin goodForm
                              Expect.equal (int response.StatusCode) 403 what

                          Expect.isEmpty (stored site) "nothing stored by a cross-site post"

                          use! ok = post site "" (Some "http://LOCALHOST") goodForm
                          Expect.equal (int ok.StatusCode) 303 "the same site, in any case"

                          let request = new HttpRequestMessage(HttpMethod.Post, "/contact")
                          request.Content <- form goodForm
                          request.Headers.Add("Referer", "http://localhost/contact")
                          use! viaReferer = site.Client.SendAsync request
                          Expect.equal (int viaReferer.StatusCode) 303 "Referer when there is no Origin"

                          let wrong = new HttpRequestMessage(HttpMethod.Post, "/contact")
                          wrong.Content <- form goodForm
                          wrong.Headers.Add("Origin", "https://evil.example")
                          wrong.Headers.Add("Referer", "http://localhost/contact")
                          use! mismatch = site.Client.SendAsync wrong
                          Expect.equal (int mismatch.StatusCode) 403 "a wrong Origin is not saved by a right Referer"
                          Expect.equal (stored site).Length 2 "only the two good posts"
                      })
          }

          testTask "the honeypot: a bot gets 200 and nothing is stored" {
              do!
                  plainSite (fun site ->
                      task {
                          use! response =
                              post
                                  site
                                  ""
                                  same
                                  [ "email", "bot@example.org"
                                    "message", "buy my pills, please"
                                    "website", "http://spam.example" ]

                          Expect.equal (int response.StatusCode) 200 "200"
                          Expect.isEmpty (stored site) "nothing stored"
                      })
          }

          testTask "a bad email or message is a 400 and nothing is stored" {
              do!
                  plainSite (fun site ->
                      task {
                          for (what, pairs) in
                              [ "no email", [ "message", "mensagem longa o bastante" ]
                                "bad email", [ "email", "not-an-email"; "message", "mensagem longa o bastante" ]
                                "no message", [ "email", "ana@example.org" ]
                                "short message", [ "email", "ana@example.org"; "message", "curta" ]
                                "a long message", [ "email", "ana@example.org"; "message", String('a', 4001) ]
                                "a NUL in the message",
                                [ "email", "ana@example.org"; "message", "mensagem\000longa o bastante" ] ] do
                              use! response = post site "" same pairs
                              Expect.equal (int response.StatusCode) 400 what

                          Expect.isEmpty (stored site) "nothing stored"
                      })
          }

          testTask "only a url-encoded form is accepted" {
              do!
                  plainSite (fun site ->
                      task {
                          let request = new HttpRequestMessage(HttpMethod.Post, "/contact")
                          request.Headers.Add("Origin", "http://localhost")

                          request.Content <-
                              new StringContent("{\"email\":\"a@b.co\"}", Text.Encoding.UTF8, "application/json")

                          use! json = site.Client.SendAsync request
                          Expect.equal (int json.StatusCode) 415 "json"

                          let multi = new HttpRequestMessage(HttpMethod.Post, "/contact")
                          multi.Headers.Add("Origin", "http://localhost")
                          let content = new MultipartFormDataContent()
                          content.Add(new StringContent "ana@example.org", "email")
                          multi.Content <- content
                          use! multipart = site.Client.SendAsync multi
                          Expect.equal (int multipart.StatusCode) 415 "multipart"
                      })
          }

          testTask "a message with SQL in it is stored as text" {
              do!
                  plainSite (fun site ->
                      task {
                          let text = "x'); drop table messages; --"
                          use! _ = post site "" same [ "email", "ana@example.org"; "message", text ]
                          use! _ = post site "" same goodForm

                          Expect.equal
                              (stored site |> List.map (fun m -> m.Body))
                              [ text; "A mensagem tem mais de dez caracteres." ]
                              "both rows"
                      })
          }

          testTask "GET /contact is the page, other methods are 405" {
              do!
                  plainSite (fun site ->
                      task {
                          use! page = site.Client.GetAsync "/contact?sent=1"
                          Expect.equal (int page.StatusCode) 200 "page"
                          use! put = site.Client.PutAsync("/contact", form goodForm)
                          Expect.equal (int put.StatusCode) 405 "PUT"
                      })
          }

          test "email syntax" {
              for good in [ "a@b.co"; "ana.silva+marola@example.com.br"; "x@a-b.example"; "  a@b.co  " ] do
                  Expect.isOk (Contact.validateEmail good) good

              for bad in
                  [ ""
                    "a"
                    "a@b"
                    "@b.co"
                    "a@@b.co"
                    "a b@c.de"
                    "a@b..de"
                    "a@-b.com"
                    "a@b-.com"
                    "<x>@y.zz"
                    "a,b@c.de"
                    "a\n@b.co"
                    "a@b.co, c@d.co"
                    "\"a\"@b.co"
                    String('a', 65) + "@b.co"
                    "a@" + String('b', 250) + ".co" ] do
                  Expect.isError (Contact.validateEmail bad) (bad.Replace('\n', '~'))

              Expect.isError (Contact.validateEmail null) "null"
          }

          test "message length: 10 to 4000 characters after trimming" {
              Expect.isError (Contact.validateMessage (String('a', 9))) "9"
              Expect.isOk (Contact.validateMessage (String('a', 10))) "10"
              Expect.isOk (Contact.validateMessage (String('a', 4000))) "4000"
              Expect.isError (Contact.validateMessage (String('a', 4001))) "4001"
              Expect.isError (Contact.validateMessage ("   " + String('a', 9) + "   ")) "spaces do not count"
              Expect.isOk (Contact.validateMessage "linha um\r\n\tlinha dois") "newline and tab"
              Expect.isError (Contact.validateMessage "linha um\u001b[31m vermelho") "an escape sequence"
              Expect.isError (Contact.validateMessage null) "null"
          }

          test "sameSite" {
              Expect.isTrue (Contact.sameSite "marola.piabrota.art" "https://marola.piabrota.art" "") "origin"
              Expect.isTrue (Contact.sameSite "127.0.0.1:8080" "http://127.0.0.1:8080" "") "with a port"
              Expect.isTrue (Contact.sameSite "marola.piabrota.art" "" "https://marola.piabrota.art/contact") "referer"

              Expect.isFalse
                  (Contact.sameSite "marola.piabrota.art" "https://marola.piabrota.art.evil.example" "")
                  "suffix"

              Expect.isFalse (Contact.sameSite "marola.piabrota.art" "" "") "neither"
              Expect.isFalse (Contact.sameSite "" "https://marola.piabrota.art" "") "no host"

              Expect.isFalse
                  (Contact.sameSite "marola.piabrota.art" "javascript:alert(1)" "")
                  "a scheme that is not http"
          }

          test "the store keeps ids, lists oldest first, deletes one, and init can run twice" {
              let db = tempDb ()

              try
                  Store.init db
                  Store.init db
                  let t = DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero)
                  let a = Store.insert db t "a@b.co" "first message"
                  let b = Store.insert db t "c@d.co" "second message"
                  Expect.equal (a, b) (1L, 2L) "ids"
                  Expect.equal (Store.list db |> List.map (fun m -> m.Id)) [ 1L; 2L ] "oldest first"
                  Expect.equal (Store.list db).Head.CreatedUtc "2026-11-11T12:00:00Z" "time"
                  Expect.isTrue (Store.delete db 1L) "deleted"
                  Expect.isFalse (Store.delete db 1L) "already gone"
                  Expect.equal (Store.list db |> List.map (fun m -> m.Id)) [ 2L ] "one left"
                  Expect.equal (Store.insert db t "e@f.co" "third message") 3L "ids are not reused"
              finally
                  cleanup db
          }

          test "inbox prints the messages, deletes one, and refuses a bad call" {
              let db = tempDb ()

              try
                  Store.init db
                  let t = DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero)
                  Store.insert db t "a@b.co" "first message\nsecond line" |> ignore
                  Store.insert db t "c@d.co" "another message" |> ignore

                  let code, out, _ = run db []
                  Expect.equal code 0 "exit"
                  Expect.stringContains out "#1  2026-11-11T12:00:00Z  a@b.co" "header"
                  Expect.stringContains out "first message\nsecond line" "body"
                  Expect.stringContains out "#2  2026-11-11T12:00:00Z  c@d.co" "second"

                  let code, out, _ = run db [ "--delete"; "1" ]
                  Expect.equal (code, out.Trim()) (0, "deleted #1") "delete"
                  let _, out, _ = run db []
                  Expect.isFalse (out.Contains "a@b.co") "gone from the list"

                  let code, _, err = run db [ "--delete"; "99" ]
                  Expect.equal (code, err.Trim()) (1, "no message #99") "missing id"
                  Expect.equal (let c, _, _ = run db [ "--delete"; "x" ] in c) 2 "not a number"
                  Expect.equal (let c, _, _ = run db [ "--delete" ] in c) 2 "no id"
                  Expect.equal (let c, _, _ = run db [ "foo" ] in c) 2 "unknown argument"
              finally
                  cleanup db
          }

          test "inbox on a missing database prints nothing and creates nothing" {
              let db = tempDb ()
              let code, out, _ = run db []
              Expect.equal (code, out) (0, "") "empty"
              Expect.isFalse (File.Exists db) "no file"
              Expect.equal (let c, _, _ = run db [ "--delete"; "1" ] in c) 1 "delete finds nothing"
              Expect.isFalse (File.Exists db) "still no file"
          }

          test "Config.fromEnv: defaults, overrides, a bad port" {
              let env (pairs: (string * string) list) name =
                  pairs |> List.tryFind (fst >> (=) name) |> Option.map snd

              match Config.fromEnv (env []) with
              | Ok c ->
                  Expect.equal c.Port 8080 "port"
                  Expect.stringEnds c.Static "app/dist" "static"
                  Expect.stringEnds c.Data "/data" "data"
                  Expect.stringEnds c.Db "data/marola.db" "db"
                  Expect.isTrue (Path.IsPathRooted c.Static) "absolute"
              | Error e -> failtest e

              match Config.fromEnv (env [ "MAROLA_PORT", "9001"; "MAROLA_DB", "/var/lib/marola/m.db" ]) with
              | Ok c -> Expect.equal (c.Port, c.Db) (9001, "/var/lib/marola/m.db") "overrides"
              | Error e -> failtest e

              for bad in [ "0"; "70000"; "x"; "" ] do
                  Expect.isError (Config.fromEnv (env [ "MAROLA_PORT", bad ])) bad
          } ]
