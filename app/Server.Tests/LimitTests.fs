module Marola.Server.Tests.LimitTests

open System.Net
open System.Net.Http
open Expecto
open Marola.Server
open Marola.Server.Tests.Harness

let private statuses (site: Site) (count: int) (peer: string) (forwarded: int -> string) =
    task {
        let codes = ResizeArray<int>()

        for i in 1..count do
            let request = new HttpRequestMessage(HttpMethod.Post, "/contact")
            request.Content <- form goodForm

            if peer <> "" then
                request.Headers.Add("X-Test-Peer", peer)

            if forwarded i <> "" then
                request.Headers.Add("X-Forwarded-For", forwarded i)

            use! response = site.Client.SendAsync request
            codes.Add(int response.StatusCode)

        return List.ofSeq codes
    }

let private ip (text: string) = IPAddress.Parse text

let tests =
    testList
        "limits and logging"
        [ testTask "the 11th POST in the window gets 429 with Retry-After and the security headers" {
              do!
                  plainSite (fun site ->
                      task {
                          // Without an Origin each POST is a 403: the limit counts requests, not outcomes.
                          let! codes = statuses site 11 "" (fun _ -> "")
                          Expect.equal (List.take 10 codes) (List.replicate 10 403) "the first ten reach the handler"
                          Expect.equal (List.last codes) 429 "the 11th is refused"

                          use! refused = post site "" None goodForm
                          Expect.equal (int refused.StatusCode) 429 "and so is the next"
                          Expect.isSome (header refused "Retry-After") "Retry-After"
                          Expect.isSome (header refused "Content-Security-Policy") "the headers are there"
                          Expect.isSome (header refused "Strict-Transport-Security") "the headers are there"
                      })
          }

          testTask "X-Forwarded-For from the loopback splits clients" {
              do!
                  plainSite (fun site ->
                      task {
                          let! a = statuses site 11 "127.0.0.1" (fun _ -> "198.51.100.1")
                          Expect.equal (List.last a) 429 "client A is over its limit"
                          let! b = statuses site 1 "127.0.0.1" (fun _ -> "198.51.100.2")
                          Expect.equal b [ 403 ] "client B has its own window"
                      })
          }

          testTask "a spoofed X-Forwarded-For from another peer is ignored" {
              do!
                  plainSite (fun site ->
                      task {
                          // A different forwarded address on each request: if it counted, no request would reach 429.
                          let! codes = statuses site 11 "203.0.113.9" (fun i -> $"198.51.100.{i}")
                          Expect.equal (List.last codes) 429 "all eleven count against the peer"
                      })
          }

          testTask "the general limit stops a flood of GETs" {
              do!
                  plainSite (fun site ->
                      task {
                          let mutable last = 0

                          for _ in 1 .. App.generalPermits + 1 do
                              use! response = site.Client.GetAsync "/index.html"
                              last <- int response.StatusCode

                          Expect.equal last 429 "request 301"
                      })
          }

          testTask "a body over 1 MB gets 413 before the handler, with the headers" {
              do!
                  plainSite (fun site ->
                      task {
                          let request = new HttpRequestMessage(HttpMethod.Post, "/contact")
                          let body = new ByteArrayContent(Array.create (int App.bodyLimit + 1) 97uy)
                          body.Headers.ContentType <- Headers.MediaTypeHeaderValue "application/x-www-form-urlencoded"
                          request.Content <- body
                          use! response = site.Client.SendAsync request
                          Expect.equal (int response.StatusCode) 413 "payload too large"
                          Expect.isSome (header response "Content-Security-Policy") "headers"
                      })
          }

          testTask "the log has the method, the path and the status, and no address, query or body" {
              do!
                  plainSite (fun site ->
                      task {
                          let request = new HttpRequestMessage(HttpMethod.Get, "/app.js?token=QUERY-SECRET")
                          request.Headers.Add("X-Forwarded-For", "203.0.113.77")
                          request.Headers.Add("X-Test-Peer", "198.51.100.200")
                          use! _ = site.Client.SendAsync request

                          use! _ =
                              post
                                  site
                                  "198.51.100.201"
                                  (Some "http://localhost")
                                  [ "email", "someone@example.org"
                                    "message", "BODY-SECRET text of the message"
                                    "website", "" ]

                          let lines = site.Capture.Lines

                          Expect.isTrue
                              (lines
                               |> List.exists (fun l -> l.Contains "GET" && l.Contains "/app.js" && l.Contains "200"))
                              "request line"

                          Expect.isTrue (lines |> List.exists (fun l -> l.Contains "stored")) "the store is logged"

                          for secret in
                              [ "QUERY-SECRET"
                                "203.0.113.77"
                                "198.51.100.200"
                                "198.51.100.201"
                                "BODY-SECRET"
                                "someone@example.org"
                                "127.0.0.1" ] do
                              Expect.isFalse
                                  (lines |> List.exists (fun l -> l.Contains secret))
                                  $"no {secret} in the log"
                      })
          }

          test "clientAddress: X-Forwarded-For counts only from the loopback, and its last entry" {
              Expect.equal (Security.clientAddress (ip "127.0.0.1") "198.51.100.1") (ip "198.51.100.1") "nginx"
              Expect.equal (Security.clientAddress (ip "::1") "198.51.100.1") (ip "198.51.100.1") "nginx on ::1"

              Expect.equal
                  (Security.clientAddress (ip "::ffff:127.0.0.1") "198.51.100.1")
                  (ip "198.51.100.1")
                  "mapped loopback"

              Expect.equal
                  (Security.clientAddress (ip "203.0.113.9") "198.51.100.1")
                  (ip "203.0.113.9")
                  "any other peer"

              Expect.equal
                  (Security.clientAddress (ip "127.0.0.1") "6.6.6.6, 198.51.100.1")
                  (ip "198.51.100.1")
                  "the last, the one nginx added"

              Expect.equal (Security.clientAddress (ip "127.0.0.1") "not an address") (ip "127.0.0.1") "garbage"
              Expect.equal (Security.clientAddress (ip "127.0.0.1") "") (ip "127.0.0.1") "no header"
          }

          test "rateKey: an IPv6 client is its /64" {
              Expect.equal
                  (Security.rateKey (ip "2001:db8:1:2:aaaa::1"))
                  (Security.rateKey (ip "2001:db8:1:2:bbbb::2"))
                  "same /64"

              Expect.notEqual
                  (Security.rateKey (ip "2001:db8:1:2::1"))
                  (Security.rateKey (ip "2001:db8:1:3::1"))
                  "another /64"

              Expect.equal (Security.rateKey (ip "198.51.100.1")) "198.51.100.1" "IPv4 as it is"
          } ]
