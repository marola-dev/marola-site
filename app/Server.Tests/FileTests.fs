module Marola.Server.Tests.FileTests

open System.Net.Http
open Expecto
open Marola.Server
open Marola.Server.Tests.Harness

/// Paths as the pipeline sees them, decoded or not. Each one must be a 404.
let private hostile =
    [ "/../secret.txt"
      "/%2e%2e/secret.txt"
      "/..%2fsecret.txt"
      "/%2e%2e%2fsecret.txt"
      "/..%5csecret.txt"
      "/..\\secret.txt"
      "/sub/../index.html"
      "/data/../secret.txt"
      "/data/..%2f..%2fsecret.txt"
      "/%252e%252e/secret.txt"
      "//index.html"
      "/sub//x.txt"
      "///"
      "/index.html\000"
      "/index.html%00"
      "/index.html\000.png"
      "/.env"
      "/sub/.hidden"
      "/.git/config"
      "/sub/"
      "/sub"
      "/index.html/"
      "/app.js/"
      "/ "
      "/index.html "
      "/C:/windows/win.ini"
      "/sub/x.txt:stream"
      "/~/x"
      "" ]

let tests =
    testList
        "static files"
        [ testTask "a hostile path is a 404 and never the secret" {
              do!
                  plainSite (fun site ->
                      task {
                          for path in hostile do
                              let! ctx = raw site "GET" path
                              Expect.equal ctx.Response.StatusCode 404 (path.Replace('\000', '0'))
                              Expect.isFalse ((bodyOf ctx).Contains secret) "the body is not a secret file"
                      })
          }

          testTask "the same paths over HTTP, as a client would write them" {
              do!
                  plainSite (fun site ->
                      task {
                          for path in
                              [ "/..%2fsecret.txt"
                                "/%2e%2e/secret.txt"
                                "/.env"
                                "/sub/.hidden"
                                "/sub//x.txt" ] do
                              use! response = site.Client.GetAsync path
                              Expect.equal (int response.StatusCode) 404 path
                              let! body = response.Content.ReadAsStringAsync()
                              Expect.isFalse (body.Contains secret) path
                      })
          }

          testTask "the page: / and /index.html, files, and a clean URL for an html file" {
              do!
                  plainSite (fun site ->
                      task {
                          for (path, kind, text) in
                              [ "/", "text/html; charset=utf-8", "home"
                                "/index.html", "text/html; charset=utf-8", "home"
                                "/app.js", "text/javascript; charset=utf-8", "export const x"
                                "/style.css", "text/css; charset=utf-8", "margin"
                                "/sub/x.txt", "text/plain; charset=utf-8", "x"
                                "/contact", "text/html; charset=utf-8", "<form>" ] do
                              use! response = site.Client.GetAsync path
                              Expect.equal (int response.StatusCode) 200 path
                              Expect.equal (header response "Content-Type") (Some kind) path
                              let! body = response.Content.ReadAsStringAsync()
                              Expect.stringContains body text path
                      })
          }

          testTask "HEAD has the headers and no body" {
              do!
                  plainSite (fun site ->
                      task {
                          use! response = site.Client.SendAsync(new HttpRequestMessage(HttpMethod.Head, "/app.js"))
                          Expect.equal (int response.StatusCode) 200 "status"
                          Expect.isSome (header response "Content-Type") "content type"
                          let! body = response.Content.ReadAsStringAsync()
                          Expect.equal body "" "no body"
                      })
          }

          testTask "/data/ reads the data folder first and the page's own data folder second" {
              do!
                  plainSite (fun site ->
                      task {
                          let! floripa = site.Client.GetStringAsync "/data/floripa/latest.json"
                          Expect.stringContains floripa "\"data\"" "the data folder wins"
                          let! rio = site.Client.GetStringAsync "/data/rio/latest.json"
                          Expect.stringContains rio "\"static\"" "the page's fixtures are the fallback"
                      })
          }

          testTask "a method other than GET and HEAD gets 405 with Allow" {
              do!
                  plainSite (fun site ->
                      task {
                          for meth in [ "PUT"; "DELETE"; "PATCH"; "POST" ] do
                              let! ctx = raw site meth "/app.js"
                              Expect.equal ctx.Response.StatusCode 405 meth
                              Expect.equal (string ctx.Response.Headers.Allow) "GET, HEAD" meth
                      })
          }

          test "segments: what is accepted and what is not" {
              Expect.equal (Files.segments "/") (Some [ "index.html" ]) "root"
              Expect.equal (Files.segments "/a/b.js") (Some [ "a"; "b.js" ]) "a file"
              Expect.equal (Files.segments "/a/") (Some [ "a"; "index.html" ]) "a folder"

              for bad in
                  [ "/.."
                    "/a/../b"
                    "/a//b"
                    "/.x"
                    "/a b"
                    "/a%2fb"
                    "/a\\b"
                    "a"
                    ""
                    "/\000" ] do
                  Expect.isNone (Files.segments bad) bad

              Expect.isNone (Files.segments ("/" + System.String('a', 600))) "a very long path"
          } ]
