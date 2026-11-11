/// The cases of scripts/news_build.py's self-test, one for one, plus the page built from the real posts.
module Marola.Pages.Tests.NewsTests

open Expecto
open Marola
open Marola.Client
open Marola.Pages
open Marola.Pages.Tests.Support

let private pt =
    "# olá\n\n2026-10-07\n\num lede.\n\n## seção\n\n- um [link](https://x.org/?a=1&b=2)\n- **dois**\n"

let private en =
    "# hello\n\n2026-10-07\n\nA lede.\n\n### sub\n\nText with `code`.\n"

let private good = [ "2026-10-07-a.pt-BR.md", pt; "2026-10-07-a.en.md", en ]

let private card =
    "::: release v0.2.1 2026-10-08\n- a [change](https://x.org/1)\n[notes](https://x.org/n) · DOI"

/// The articles of the posts in one language, as HTML text, newest first.
let private articles (language: Language) (files: (string * string) list) (index: string) : Result<string, string> =
    News.build files index
    |> Result.map (fun posts ->
        News.forLanguage language posts
        |> List.map (fun p -> Vdom.toHtml p.Article)
        |> String.concat "\n")

let private ok (language: Language) files index : string =
    match articles language files index with
    | Ok html -> html
    | Error e -> failwith e

let private fails (label: string) files index =
    test label {
        Expect.isError (articles Language.PtBr files index) label
        Expect.isError (articles Language.En files index) label
    }

let private has (needle: string) (html: string) = html.Contains needle

let private replaceEn (text: string) =
    [ "2026-10-07-a.pt-BR.md", pt; "2026-10-07-a.en.md", text ]

let tests =
    testList
        "news"
        [ test "a post in both languages passes" {
              Expect.isNonEmpty (ok Language.PtBr good "2026-10-07-a") "pt-BR"
              Expect.isNonEmpty (ok Language.En good "2026-10-07-a") "en"
          }
          test "pt-BR date and reading time" {
              Expect.isTrue
                  (has
                      "<time datetime=\"2026-10-07\">7 de outubro de 2026</time> · 1 min de leitura</p>"
                      (ok Language.PtBr good "2026-10-07-a"))
                  "date"
          }
          test "en date and reading time" {
              Expect.isTrue (has "October 7, 2026</time> · 1 min read</p>" (ok Language.En good "2026-10-07-a")) "date"
          }
          test "201 words round up to 2 minutes" {
              Expect.equal (News.readingMinutes [ "# t"; String.replicate 200 "word " ]) 2 "minutes"
              Expect.equal (News.readingMinutes [ "# t"; String.replicate 199 "word " ]) 1 "minutes"
          }
          test "link targets and markup are not counted" {
              Expect.equal (News.words [ "[two words](https://a.org/x/y/z)"; "- **one** ·" ] |> List.length) 3 "words"
          }
          test "the paragraph after the date is the lede" {
              Expect.isTrue (has "<p class=\"lede\">um lede.</p>" (ok Language.PtBr good "2026-10-07-a")) "lede"
          }
          test "a link's & is escaped once" {
              Expect.isTrue
                  (has "<a href=\"https://x.org/?a=1&amp;b=2\">link</a>" (ok Language.PtBr good "2026-10-07-a"))
                  "link"
          }
          test "bold and code render" {
              Expect.isTrue (has "<li><b>dois</b></li>" (ok Language.PtBr good "2026-10-07-a")) "bold"
              Expect.isTrue (has "<code>code</code>" (ok Language.En good "2026-10-07-a")) "code"
          }
          test "each language page shows only its own posts" {
              let pt' = ok Language.PtBr good "2026-10-07-a"
              let en' = ok Language.En good "2026-10-07-a"
              Expect.isTrue (has "lang=\"pt-BR\"" pt' && not (has "lang=\"en\"" pt')) "pt-BR"
              Expect.isTrue (has "lang=\"en\"" en' && not (has "lang=\"pt-BR\"" en')) "en"
          }
          test "a release card renders" {
              let html = ok Language.En (replaceEn (en + "\n" + card + "\n")) "2026-10-07-a"

              Expect.isTrue
                  (has "href=\"https://github.com/marola-dev/marola/releases/tag/v0.2.1\">marola v0.2.1</a>" html
                   && has "October 8, 2026" html
                   && has "<p class=\"release-links\"><a href=\"https://x.org/n\">notes</a> · DOI</p>" html)
                  "tag, date, highlights and links"
          }
          fails
              "a release card with no links line fails"
              (replaceEn (en + "\n::: release v0.2.1 2026-10-08\n- one\n"))
              "2026-10-07-a"
          fails "a post with no en file fails" [ "2026-10-07-a.pt-BR.md", pt ] "2026-10-07-a"
          fails
              "a date line that is not the file's date fails"
              (replaceEn (en.Replace("2026-10-07", "2026-10-08")))
              "2026-10-07-a"
          fails "a badly named file fails" ([ "post.en.md", en ] @ good) "2026-10-07-a"
          fails "an unsupported heading fails" (replaceEn (en + "\n#### deep\n")) "2026-10-07-a"
          fails "leftover Markdown fails" (replaceEn (en + "\n_italic_\n")) "2026-10-07-a"
          test "raw HTML is escaped, not passed through" {
              let html = ok Language.En (replaceEn (en + "\n<script>x</script>\n")) "2026-10-07-a"
              Expect.isTrue (has "&lt;script&gt;x&lt;/script&gt;" html && not (has "<script" html)) "escaped"
          }
          fails "a post missing from the README index fails" good ""
          test "two posts pass, newest first" {
              let newer =
                  good
                  @ [ "2026-10-09-b.pt-BR.md", pt.Replace("2026-10-07", "2026-10-09")
                      "2026-10-09-b.en.md", en.Replace("2026-10-07", "2026-10-09") ]

              let html = ok Language.En newer "2026-10-07-a 2026-10-09-b"
              Expect.isTrue (html.IndexOf "datetime=\"2026-10-09\"" < html.IndexOf "datetime=\"2026-10-07\"") "order"
          }
          test "a sibling page link such as about.html is allowed and anything else relative is not" {
              let withLink (url: string) =
                  replaceEn (en.Replace("A lede.", "A [lede](" + url + ")."))

              Expect.isOk (articles Language.En (withLink "about.html") "2026-10-07-a") "sibling"
              Expect.isError (articles Language.En (withLink "../about") "2026-10-07-a") "relative"
          }
          test "the news page of each language lists the repo's posts under the nav and the shared head" {
              for language in Language.all do
                  let html = render "news" language
                  Expect.isTrue (has "aria-current=\"page\"" html) "nav mark"
                  Expect.isTrue (has "class=\"post-date\"" html) "posts"
          } ]
