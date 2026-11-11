/// escapeHtml and safeHref, with the inputs an attacker would try.
module Marola.Tests.HtmlTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola

let tests =
    testList
        "html"
        [ testCase "escapeHtml escapes the five characters"
          <| fun () ->
              Expect.equal
                  (Html.escapeHtml "<a href=\"x\" title='y'>&</a>")
                  "&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt;&amp;&lt;/a&gt;"
                  "five"

          testCase "escapeHtml does not escape twice and keeps other text"
          <| fun () ->
              Expect.equal (Html.escapeHtml "&lt;") "&amp;lt;" "ampersand first"
              Expect.equal (Html.escapeHtml "") "" "empty"
              Expect.equal (Html.escapeHtml "ação · 日本 😀") "ação · 日本 😀" "unicode"

          testCase "safeHref allows http, https and mailto"
          <| fun () ->
              Expect.equal (Html.safeHref "https://example.com/a?b=c#d") (Some "https://example.com/a?b=c#d") "https"
              Expect.equal (Html.safeHref "http://example.org") (Some "http://example.org") "http"
              Expect.equal (Html.safeHref "mailto:oi@marola.dev") (Some "mailto:oi@marola.dev") "mailto"

          testCase "safeHref ignores the case of the scheme"
          <| fun () ->
              Expect.equal (Html.safeHref "HTTPS://EXAMPLE.COM") (Some "HTTPS://EXAMPLE.COM") "https"
              Expect.equal (Html.safeHref "MailTo:a@b.c") (Some "MailTo:a@b.c") "mailto"

          testCase "safeHref reads the URL as a browser does"
          <| fun () ->
              Expect.equal (Html.safeHref "  https://a.com  ") (Some "https://a.com") "spaces"
              Expect.equal (Html.safeHref "\u0001\u0002 https://a.com") (Some "https://a.com") "controls"
              Expect.equal (Html.safeHref "https://a.com/x\ty\nz") (Some "https://a.com/xyz") "tab and newline"
              Expect.equal (Html.safeHref "https://a.com/\u0000") (Some "https://a.com/") "trailing nul"

          testCase "safeHref refuses script and data schemes"
          <| fun () ->
              for url in
                  [ "javascript:alert(1)"
                    "JaVaScRiPt:alert(1)"
                    "JAVASCRIPT:alert(1)"
                    " javascript:alert(1)"
                    "\u0000javascript:alert(1)"
                    "\u001Fjavascript:alert(1)"
                    "java\tscript:alert(1)"
                    "java\nscript:alert(1)"
                    "java\rscript:alert(1)"
                    "j\u0000avascript:alert(1)"
                    "javascript\t:alert(1)"
                    "data:text/html,<script>alert(1)</script>"
                    "DATA:text/html;base64,PHNjcmlwdD4="
                    "vbscript:msgbox(1)"
                    "file:///etc/passwd"
                    "ftp://example.com"
                    "blob:https://example.com/x" ] do
                  Expect.equal (Html.safeHref url) None url

          testCase "safeHref refuses what is not an absolute link"
          <| fun () ->
              for url in
                  [ ""
                    " "
                    "\t\n"
                    "//evil.example"
                    "/relative"
                    "#fragment"
                    "?q=1"
                    "https"
                    "https//example.com"
                    "https:"
                    "mailto:"
                    "ht tps://example.com"
                    "\uFEFFhttps://example.com"
                    "ｈttps://example.com"
                    "1http://x.y"
                    "javascript&colon;alert(1)"
                    "https://example.com/\u0000x"
                    "https://example.com/\u007F"
                    "https://example.com/\u0085" ] do
                  Expect.equal (Html.safeHref url) None url

          testCase "safeHref only ever returns an allowed scheme"
          <| fun () ->
              for url in
                  [ "javascript:1"
                    "https://a.b"
                    "\thttp://a.b"
                    "mailto:x@y"
                    "data:x"
                    "  HTTPS://A.B"
                    "java\u0009script:1"
                    "x:y" ] do
                  match Html.safeHref url with
                  | None -> ()
                  | Some href ->
                      let lower = href.ToLowerInvariant()

                      Expect.isTrue
                          (lower.StartsWith "https:"
                           || lower.StartsWith "http:"
                           || lower.StartsWith "mailto:")
                          href

                      Expect.isFalse (href.Contains "\t") href ]
