/// The F# pages against the old static pages that scripts/news_build.py and scripts/members_build.py
/// wrote into site/static: the same posts in the same order, the same people in the same order. The old
/// files stay until the cutover, and these tests are what lets the new build replace them.
module Marola.Pages.Tests.EqualityTests

open System.IO
open System.Net
open System.Text.RegularExpressions
open Expecto
open Marola
open Marola.Pages
open Marola.Pages.Tests.Support

let private old (name: string) =
    File.ReadAllText(Path.Combine(root, "site/static", name))

let private articles (language: Language) (html: string) : string list =
    Regex.Matches(
        html,
        "<article class=\"about-body\" lang=\""
        + Language.tag language
        + "\">(.*?)</article>",
        RegexOptions.Singleline
    )
    |> Seq.map (fun m -> m.Groups[1].Value)
    |> List.ofSeq

/// What a reader reads: tags dropped, entities decoded, runs of space collapsed.
let private visible (html: string) : string =
    Regex.Replace(WebUtility.HtmlDecode(Regex.Replace(html, "<[^>]*>", " ")), @"\s+", " ").Trim()

let private firstH2 (article: string) : string =
    visible (Regex.Match(article, "<h2>(.*?)</h2>", RegexOptions.Singleline).Groups[1].Value)

let private hrefs (html: string) : string list =
    Regex.Matches(html, "<a [^>]*href=\"([^\"]*)\"")
    |> Seq.map (fun m -> WebUtility.HtmlDecode m.Groups[1].Value)
    |> List.ofSeq

let tests =
    testList
        "equality with the old static pages"
        [ test "news: the same posts, in the same order, in each language" {
              let oldPage = old "news.html"

              for language in Language.all do
                  let oldArticles = articles language oldPage
                  let newArticles = articles language (render "news" language)
                  Expect.isNonEmpty oldArticles "old posts"
                  Expect.equal (List.map firstH2 newArticles) (List.map firstH2 oldArticles) (Language.tag language)
          }
          test "news: the same words, reading time and links in each post" {
              let oldPage = old "news.html"

              for language in Language.all do
                  let oldArticles = articles language oldPage
                  let newArticles = articles language (render "news" language)
                  Expect.equal (List.length newArticles) (List.length oldArticles) "count"

                  for o, n in List.zip oldArticles newArticles do
                      Expect.equal (visible n) (visible o) (Language.tag language + " " + firstH2 o)
                      Expect.equal (hrefs n) (hrefs o) (Language.tag language + " links of " + firstH2 o)
          }
          test "members: the same people, in the same order, the same count, in each language" {
              let oldPage = old "members.html"

              for language in Language.all do
                  let names (html: string) =
                      Regex.Matches(html, "<span class=\"member-name\">([^<]*)</span>")
                      |> Seq.map (fun m -> WebUtility.HtmlDecode m.Groups[1].Value)
                      |> List.ofSeq

                  let oldNames = names (List.head (articles language oldPage))
                  let newNames = names (List.head (articles language (render "members" language)))
                  Expect.isNonEmpty oldNames "old members"
                  Expect.equal newNames oldNames (Language.tag language)
          }
          test "members: the same words and links per language, and local avatars only" {
              let oldPage = old "members.html"

              for language in Language.all do
                  let o = List.head (articles language oldPage)
                  let page = render "members" language
                  let n = List.head (articles language page)
                  Expect.equal (visible n) (visible o) (Language.tag language)
                  Expect.equal (hrefs n) (hrefs o) (Language.tag language + " links")

                  let srcs =
                      Regex.Matches(page, "<img [^>]*src=\"([^\"]*)\"")
                      |> Seq.map (fun m -> m.Groups[1].Value)
                      |> List.ofSeq

                  Expect.isNonEmpty srcs "avatars"
                  Expect.isTrue (srcs |> List.forall (fun s -> s.StartsWith "/img/members/")) "no avatar from GitHub"
          }
          test "humans.txt: the same team as the old file" {
              let team (text: string) =
                  let start = text.IndexOf "Name: "
                  text.Substring(start, text.IndexOf "/* SITE */" - start)

              match Members.parse env.Members with
              | Ok members -> Expect.equal (team (Members.humans members)) (team (old "humans.txt")) "team"
              | Error e -> failwith e
          }
          test "robots.txt: the same as the old file" { Expect.equal Meta.robots (old "robots.txt") "robots" } ]
