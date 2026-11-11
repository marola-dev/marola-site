module Marola.Server.Tests.HeaderTests

open System
open System.Net.Http
open Expecto
open Microsoft.AspNetCore.Builder
open Marola
open Marola.Server.Tests.Harness

let private expected =
    [ "Content-Security-Policy", Csp.policy () + "; form-action 'self'"
      "Strict-Transport-Security", "max-age=63072000; includeSubDomains"
      "X-Content-Type-Options", "nosniff"
      "Referrer-Policy", "strict-origin-when-cross-origin"
      "Permissions-Policy", "geolocation=(self), camera=(), microphone=(), payment=(), usb=()"
      "Cross-Origin-Opener-Policy", "same-origin"
      "Cross-Origin-Resource-Policy", "same-origin" ]

let private checkHeaders (what: string) (response: HttpResponseMessage) =
    for (name, value) in expected do
        Expect.equal (header response name) (Some value) $"{what}: {name}"

    Expect.isNone (header response "Server") $"{what}: no Server header"
    Expect.isNone (header response "X-Powered-By") $"{what}: no X-Powered-By header"

let private boom (app: WebApplication) =
    app.MapGet("/boom", Func<string>(fun () -> failwith "DETAIL-THAT-MUST-NOT-LEAK"))
    |> ignore

let private send (site: Site) (meth: string) (path: string) (encoding: string) =
    let request = new HttpRequestMessage(HttpMethod(meth), path)

    if encoding <> "" then
        request.Headers.Add("Accept-Encoding", encoding)

    site.Client.SendAsync request

let tests =
    testList
        "headers"
        [ testTask "every header is on 200, 404, HEAD, 405, 500 and a rejected POST" {
              do!
                  withSite boom (fun site ->
                      task {
                          for (what, meth, path, status) in
                              [ "200", "GET", "/", 200
                                "404", "GET", "/nope", 404
                                "HEAD", "HEAD", "/", 200
                                "405", "PUT", "/", 405
                                "500", "GET", "/boom", 500
                                "403", "POST", "/contact", 403 ] do
                              use! response = send site meth path ""
                              Expect.equal (int response.StatusCode) status $"{what}: status"
                              checkHeaders what response
                      })
          }

          testTask "a 500 has no stack trace and no detail, and the log keeps the cause" {
              do!
                  withSite boom (fun site ->
                      task {
                          use! response = send site "GET" "/boom" ""
                          let! body = response.Content.ReadAsStringAsync()
                          Expect.equal body "internal server error\n" "plain page"
                          Expect.isFalse (body.Contains "DETAIL") "the exception message stays in the log"
                          Expect.isFalse (body.Contains " at ") "no stack trace"

                          Expect.isTrue
                              (site.Capture.Lines
                               |> List.exists (fun l -> l.Contains "DETAIL-THAT-MUST-NOT-LEAK"))
                              "the log keeps the cause"
                      })
          }

          testTask "cache: no-cache for html and json, a day for fonts and images, immutable for hashed files" {
              do!
                  plainSite (fun site ->
                      task {
                          for (path, cache) in
                              [ "/", "no-cache"
                                "/index.html", "no-cache"
                                "/app.js", "no-cache"
                                "/style.css", "no-cache"
                                "/data/floripa/latest.json", "no-cache"
                                "/font.woff2", "public, max-age=86400"
                                "/photo.png", "public, max-age=86400"
                                "/logo.svg", "public, max-age=86400"
                                "/app.1a2b3c4d5e.js", "public, max-age=31536000, immutable" ] do
                              use! response = send site "GET" path ""
                              Expect.equal (header response "Cache-Control") (Some cache) path
                      })
          }

          testTask "a repeat request with the ETag gets 304 and the headers" {
              do!
                  plainSite (fun site ->
                      task {
                          use! first = send site "GET" "/app.js" ""
                          let etag = (header first "ETag").Value
                          let request = new HttpRequestMessage(HttpMethod.Get, "/app.js")
                          request.Headers.Add("If-None-Match", etag)
                          use! second = site.Client.SendAsync request
                          Expect.equal (int second.StatusCode) 304 "not modified"
                          checkHeaders "304" second
                      })
          }

          testTask "text types are compressed with br or gzip, binary types are not" {
              do!
                  plainSite (fun site ->
                      task {
                          for path in [ "/"; "/app.js"; "/style.css"; "/logo.svg"; "/data/floripa/latest.json" ] do
                              use! br = send site "GET" path "br, gzip"
                              Expect.equal (header br "Content-Encoding") (Some "br") $"{path} br"
                              use! gz = send site "GET" path "gzip"
                              Expect.equal (header gz "Content-Encoding") (Some "gzip") $"{path} gzip"

                          for path in [ "/font.woff2"; "/photo.png" ] do
                              use! response = send site "GET" path "br, gzip"
                              Expect.isNone (header response "Content-Encoding") $"{path} is sent as it is"

                          use! plain = send site "GET" "/app.js" ""
                          Expect.isNone (header plain "Content-Encoding") "no Accept-Encoding, no compression"
                          use! compressed = send site "GET" "/app.js" "br"
                          checkHeaders "compressed" compressed
                      })
          } ]
