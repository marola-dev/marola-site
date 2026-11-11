module Marola.Pages.Tests.MarkdownTests

open Expecto
open Marola.Client
open Marola.Pages

let private head = "title: t\ndescription: d\n\n"

let private body (text: string) : string =
    match Markdown.parse (head + text) with
    | Ok doc -> doc.Body |> List.map Vdom.toHtml |> String.concat ""
    | Error e -> failwith e

let private fails (text: string) : bool =
    match Markdown.parse (head + text) with
    | Error _ -> true
    | Ok _ -> false

let tests =
    testList
        "Markdown"
        [ test "headings, paragraphs that wrap, lists and inline marks" {
              Expect.equal
                  (body
                      "## one\n\ntwo\nlines with `code` and **bold** and [a link](https://x.org/?a=1&b=2)\n\n- first\n- second")
                  "<h2>one</h2><p>two lines with <code>code</code> and <b>bold</b> and <a href=\"https://x.org/?a=1&amp;b=2\">a link</a></p><ul><li>first</li><li>second</li></ul>"
                  "html"
          }
          test "a lede, a quote with a language and a source, a figure, a disabled item" {
              Expect.equal
                  (body
                      "::lede big\n\n> @en\n> \"q\"\n> -- by [me](/x)\n\n![alt \"a\"](/img/a.svg 10x20)\ncaption\n\n- {{soon Coffee|soon}}")
                  "<p class=\"lede\">big</p><blockquote lang=\"en\"><p>\"q\"</p><footer>by <a href=\"/x\">me</a></footer></blockquote><figure><a href=\"/img/a.svg\"><img src=\"/img/a.svg\" width=\"10\" height=\"20\" alt=\"alt &quot;a&quot;\"></a><figcaption>caption</figcaption></figure><ul><li><span aria-disabled=\"true\">Coffee <i>soon</i></span></li></ul>"
                  "html"
          }
          test "a comment line is dropped" { Expect.equal (body "%% note\n\ntext") "<p>text</p>" "comment" }
          test "text that looks like markup stays text" {
              Expect.equal (body "a <script>x</script> b") "<p>a &lt;script&gt;x&lt;/script&gt; b</p>" "escaped"
          }
          test "what the subset does not have is an error, not output" {
              Expect.isTrue (fails "[x](javascript:alert(1))") "javascript link"
              Expect.isTrue (fails "[x](//evil.example/)") "protocol-relative link"
              Expect.isTrue (fails "<div>x</div>") "raw html"
              Expect.isTrue (fails "#### deep") "heading level"
              Expect.isTrue (fails "_italic_ and *star*") "emphasis"
              Expect.isTrue (fails "an `unclosed code") "unclosed"
              Expect.isTrue (fails "- one\n  wraps") "wrapped item"
          }
          test "a page without title and description is an error" {
              Expect.isTrue (Result.isError (Markdown.parse "## only a heading")) "head fields required"
          } ]
