module Marola.Server.Tests.LoginTests

open System
open System.Net
open System.Net.Http
open Expecto
open Marola.Server
open Marola.Server.Tests.Harness

let private token = "gho_FAKE_ACCESS_TOKEN_0123456789"

let private json (status: HttpStatusCode) (body: string) =
    new HttpResponseMessage(status, Content = new StringContent(body, Text.Encoding.UTF8, "application/json"))

/// A GitHub that confirms the code and says who the user is.
let private friendly (site: Site) =
    site.Github.Respond <-
        fun request _ ->
            match request.RequestUri.AbsolutePath with
            | "/login/oauth/access_token" ->
                json HttpStatusCode.OK ("{\"access_token\":\"" + token + "\",\"token_type\":\"bearer\"}")
            | "/user" ->
                json
                    HttpStatusCode.OK
                    "{\"id\":4242,\"login\":\"ana-bia\",\"created_at\":\"2020-05-06T07:08:09Z\",\"email\":\"never@example.org\"}"
            | _ -> new HttpResponseMessage(HttpStatusCode.NotFound)

let private get (site: Site) (url: string) (cookie: string option) =
    let request = new HttpRequestMessage(HttpMethod.Get, url)
    cookie |> Option.iter (fun c -> request.Headers.Add("Cookie", c))
    site.Client.SendAsync request

/// The state the server gave, as the cookie a browser would send back.
let private startLogin (site: Site) =
    task {
        use! login = get site "/auth/github/login" None
        let state = (cookies login)["__Host-mstate"]
        let query = Web.HttpUtility.ParseQueryString login.Headers.Location.Query
        return state, query["state"]
    }

let tests =
    testList
        "github login"
        [ testTask "login redirects to GitHub with a state, an empty scope and a Secure HttpOnly Lax cookie" {
              do!
                  plainSite (fun site ->
                      task {
                          use! login = get site "/auth/github/login" None
                          Expect.equal (int login.StatusCode) 302 "redirect"
                          let url = login.Headers.Location

                          Expect.equal
                              (url.GetLeftPart UriPartial.Path)
                              "https://github.test/login/oauth/authorize"
                              "github"

                          let query = Web.HttpUtility.ParseQueryString url.Query
                          Expect.equal query["client_id"] "test-client-id" "client id"
                          Expect.isNull query["scope"] "no scope: public data only"
                          Expect.isNull query["client_secret"] "never in the URL"
                          let cookie = setCookieHeader login "__Host-mstate"
                          Expect.stringContains cookie "httponly" "HttpOnly"
                          Expect.stringContains cookie "secure" "Secure"
                          Expect.stringContains cookie "samesite=lax" "Lax"
                          Expect.stringContains cookie "path=/" "path"
                          Expect.isFalse (cookie.Contains "domain") "no domain"
                          Expect.stringContains cookie "max-age=600" "10 minutes"
                          let held = (cookies login).["__Host-mstate"]
                          Expect.stringContains held query["state"] "the cookie holds the state"
                      })
          }
          testTask "a good callback makes the account at GitHub's date, starts a session and drops the token" {
              do!
                  plainSite (fun site ->
                      task {
                          friendly site
                          let! state, param = startLogin site

                          use! back =
                              get
                                  site
                                  ("/auth/github/callback?code=abc123&state=" + param)
                                  (Some("__Host-mstate=" + state))

                          Expect.equal (int back.StatusCode) 303 "redirect"
                          Expect.equal (string back.Headers.Location) "/account" "to the account"
                          let session = setCookieHeader back "__Host-msess"
                          Expect.stringContains session "httponly" "HttpOnly"
                          Expect.stringContains session "secure" "Secure"
                          Expect.stringContains session "samesite=lax" "Lax"

                          match StudyStore.getAccount site.Config.Db 4242L with
                          | Some a ->
                              Expect.equal (a.Login, a.CreatedGithubUtc) ("ana-bia", "2020-05-06T07:08:09Z") "profile"
                          | None -> failtest "no account"

                          let live =
                              StudyStore.getSession site.Config.Db site.Clock.Now (cookies back).["__Host-msess"]

                          Expect.isSome live "the session works"

                          // The token left the request: GitHub got it once, and nothing keeps it.
                          let seen = site.Github.Seen |> Seq.toList
                          Expect.equal seen.Length 2 "token call and user call"
                          let _, _, tokenBody = seen[0]
                          Expect.stringContains tokenBody fakeClientSecret "the secret goes to GitHub, server side"
                          let _, auth, _ = seen[1]
                          Expect.equal auth ("Bearer " + token) "the user call"
                          let everything = String.concat "\n" site.Capture.Lines
                          Expect.isFalse (everything.Contains token) "no token in the log"
                          Expect.isFalse (everything.Contains fakeClientSecret) "no secret in the log"
                          Expect.isFalse (everything.Contains "abc123") "no code in the log"
                          Expect.isFalse (session.Contains token) "no token in the cookie"
                          // The state cookie is single use.
                          Expect.stringContains
                              (setCookieHeader back "__Host-mstate")
                              "expires=Thu, 01 Jan 1970"
                              "cleared"
                      })
          }
          testTask "an English login returns to /en/account; a returning user keeps the id and takes the new login" {
              do!
                  plainSite (fun site ->
                      task {
                          friendly site
                          use! login = get site "/auth/github/login?lang=en" None
                          let state = (cookies login)["__Host-mstate"]
                          let param = (Web.HttpUtility.ParseQueryString login.Headers.Location.Query)["state"]

                          use! back =
                              get site ("/auth/github/callback?code=c&state=" + param) (Some("__Host-mstate=" + state))

                          Expect.equal (string back.Headers.Location) "/en/account" "english"

                          site.Github.Respond <-
                              fun request _ ->
                                  match request.RequestUri.AbsolutePath with
                                  | "/login/oauth/access_token" ->
                                      json HttpStatusCode.OK ("{\"access_token\":\"" + token + "\"}")
                                  | _ ->
                                      json
                                          HttpStatusCode.OK
                                          "{\"id\":4242,\"login\":\"ana-renamed\",\"created_at\":\"2020-05-06T07:08:09Z\"}"

                          let! state2, param2 = startLogin site

                          use! again =
                              get
                                  site
                                  ("/auth/github/callback?code=c&state=" + param2)
                                  (Some("__Host-mstate=" + state2))

                          Expect.equal (int again.StatusCode) 303 "ok"

                          Expect.equal
                              (StudyStore.getAccount site.Config.Db 4242L |> Option.map _.Login)
                              (Some "ana-renamed")
                              "renamed"
                      })
          }
          testTask "a wrong, missing or replayed state is refused and nothing is created" {
              do!
                  plainSite (fun site ->
                      task {
                          friendly site
                          let! state, param = startLogin site
                          let cookie = Some("__Host-mstate=" + state)
                          use! wrong = get site "/auth/github/callback?code=c&state=0000" cookie
                          Expect.equal (int wrong.StatusCode) 400 "wrong state"
                          use! missing = get site ("/auth/github/callback?code=c&state=" + param) None
                          Expect.equal (int missing.StatusCode) 400 "no cookie"
                          use! empty = get site "/auth/github/callback?code=c&state=" (Some "__Host-mstate=.pt")
                          Expect.equal (int empty.StatusCode) 400 "empty state"
                          use! nocode = get site ("/auth/github/callback?state=" + param) cookie
                          Expect.equal (int nocode.StatusCode) 400 "no code"
                          Expect.isEmpty (site.Github.Seen |> Seq.toList) "GitHub was never called"
                          Expect.isNone (StudyStore.getAccount site.Config.Db 4242L) "no account"
                          Expect.isFalse (cookies wrong |> Map.containsKey "__Host-msess") "no session"
                      })
          }
          testTask "a GitHub error shows no detail from GitHub and creates nothing" {
              do!
                  plainSite (fun site ->
                      task {
                          let ask () =
                              task {
                                  let! state, param = startLogin site

                                  return!
                                      get
                                          site
                                          ("/auth/github/callback?code=c&state=" + param)
                                          (Some("__Host-mstate=" + state))
                              }

                          site.Github.Respond <-
                              fun _ _ ->
                                  json
                                      HttpStatusCode.OK
                                      "{\"error\":\"bad_verification_code\",\"error_description\":\"The code passed is incorrect\"}"

                          use! a = ask ()
                          Expect.equal (int a.StatusCode) 502 "no token"
                          let! text = a.Content.ReadAsStringAsync()

                          Expect.isFalse
                              (text.Contains "bad_verification_code" || text.Contains "incorrect")
                              "no detail"

                          site.Github.Respond <-
                              fun r _ ->
                                  if r.RequestUri.AbsolutePath = "/user" then
                                      json HttpStatusCode.InternalServerError "{}"
                                  else
                                      json HttpStatusCode.OK ("{\"access_token\":\"" + token + "\"}")

                          use! b = ask ()
                          Expect.equal (int b.StatusCode) 502 "user call failed"

                          site.Github.Respond <-
                              fun r _ ->
                                  if r.RequestUri.AbsolutePath = "/user" then
                                      json HttpStatusCode.OK "{\"id\":\"x\",\"login\":\"a b\"}"
                                  else
                                      json HttpStatusCode.OK ("{\"access_token\":\"" + token + "\"}")

                          use! c = ask ()
                          Expect.equal (int c.StatusCode) 502 "a profile of the wrong shape"

                          site.Github.Respond <- fun _ _ -> raise (HttpRequestException("boom " + token))
                          use! d = ask ()
                          Expect.equal (int d.StatusCode) 502 "network error"
                          Expect.isNone (StudyStore.getAccount site.Config.Db 4242L) "no account"
                          Expect.isFalse ((String.concat "\n" site.Capture.Lines).Contains token) "no token in the log"
                      })
          }
          testTask "without the client id or the secret file login answers 503 and the rest of the site works" {
              for tweak in
                  [ (fun (c: Config) -> { c with GithubClientId = None })
                    (fun (c: Config) -> { c with GithubSecretFile = None })
                    (fun (c: Config) ->
                        { c with
                            GithubSecretFile = Some "/nonexistent/secret" }) ] do
                  do!
                      withSite' tweak (fun site ->
                          task {
                              use! login = get site "/auth/github/login" None
                              Expect.equal (int login.StatusCode) 503 "login"
                              use! back = get site "/auth/github/callback?code=c&state=s" None
                              Expect.equal (int back.StatusCode) 503 "callback"
                              use! home = get site "/contact.html" None
                              Expect.equal (int home.StatusCode) 200 "the site"
                          })
          } ]
