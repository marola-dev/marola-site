module Marola.Pages.Tests.PageTests

open System.Text.RegularExpressions
open Expecto
open Marola
open Marola.Pages
open Marola.Pages.Tests.Support

let private cases =
    [ for slug in Site.allSlugs do
          for language in Language.all do
              yield slug, language ]

let private has (needle: string) (html: string) : bool = html.Contains needle

let private hrefs (html: string) : string list =
    Regex.Matches(html, "href=\"([^\"]*)\"")
    |> Seq.map (fun m -> m.Groups[1].Value)
    |> List.ofSeq

let private forEach (what: string) (check: string -> Language -> string -> unit) =
    test what {
        for slug, language in cases do
            check slug language (render slug language)
    }

let tests =
    testList
        "pages"
        [ forEach "the document has its language, a favicon and the shared style" (fun slug language html ->
              let where = slug + " " + Language.tag language
              Expect.isTrue (html.StartsWith("<!doctype html>\n<html lang=\"" + Language.tag language + "\">")) where
              Expect.isTrue (has "<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">" html) where
              Expect.isTrue (has "<link rel=\"stylesheet\" href=\"/style.css\">" html) where)
          forEach "canonical and the three alternates point at the page's own files" (fun slug language html ->
              let where = slug + " " + Language.tag language

              if slug = "404" then
                  Expect.isFalse (has "rel=\"canonical\"" html) (where + ": a 404 has no canonical")
              else
                  let own = Layout.origin + Layout.path language slug
                  Expect.isTrue (has ("<link rel=\"canonical\" href=\"" + own + "\">") html) where

                  Expect.isTrue
                      (has
                          ("hreflang=\"pt-BR\" href=\""
                           + Layout.origin
                           + Layout.path Language.PtBr slug
                           + "\"")
                          html)
                      where

                  Expect.isTrue
                      (has ("hreflang=\"en\" href=\"" + Layout.origin + Layout.path Language.En slug + "\"") html)
                      where

                  Expect.isTrue
                      (has
                          ("hreflang=\"x-default\" href=\""
                           + Layout.origin
                           + Layout.path Language.PtBr slug
                           + "\"")
                          html)
                      where)
          forEach "no script, no style element, no style attribute, no handler" (fun slug language html ->
              let where = slug + " " + Language.tag language
              Expect.isFalse (Regex.IsMatch(html, "<script|<style| style=| on[a-z]+=", RegexOptions.IgnoreCase)) where)
          forEach "the language switch is two plain links to this page in each language" (fun slug language html ->
              let where = slug + " " + Language.tag language
              Expect.isTrue (has ("<a href=\"" + Layout.path Language.PtBr slug + "\" lang=\"pt-BR\"") html) where
              Expect.isTrue (has ("<a href=\"" + Layout.path Language.En slug + "\" lang=\"en\"") html) where)
          forEach "the nav links go to the page's own language" (fun slug language html ->
              let where = slug + " " + Language.tag language

              for nav in Layout.navSlugs do
                  Expect.isTrue (List.contains (Layout.path language nav) (hrefs html)) (where + " " + nav))
          test "every nav link has a page in the build" {
              for slug in Layout.navSlugs do
                  Expect.isTrue (List.contains slug Site.allSlugs) (slug + " has no page")
          }
          test "only the contact pages and the 404 stay out of search results" {
              for slug, language in cases do
                  let html = render slug language
                  let hidden = List.contains slug [ "contact"; "contact-sent"; "404" ]

                  Expect.equal
                      (has "<meta name=\"robots\" content=\"noindex\">" html)
                      hidden
                      (slug + " " + Language.tag language)
          }
          test "the contact form posts to the language's own path, with a honeypot and a required email" {
              for language, action in [ Language.PtBr, "/contact"; Language.En, "/en/contact" ] do
                  let html = render "contact" language
                  Expect.isTrue (has ("<form class=\"contact\" action=\"" + action + "\" method=\"POST\">") html) action

                  Expect.isTrue
                      (has "name=\"website\" tabindex=\"-1\" autocomplete=\"off\" aria-hidden=\"true\" hidden=\"\"" html)
                      "honeypot"

                  Expect.isTrue
                      (has "<input type=\"email\" name=\"email\" required=\"\" autocomplete=\"email\">" html)
                      "email"

                  Expect.isTrue (has "<textarea name=\"message\" rows=\"6\" required=\"\"></textarea>" html) "message"
          }
          test "the other pages have no form" {
              for slug, language in cases do
                  if slug <> "contact" then
                      Expect.isFalse (has "<form" (render slug language)) slug
          }
          test "about keeps its credits and the map's sources, in both languages" {
              for language in Language.all do
                  let html = render "about" language

                  for needle in
                      [ "Carlos Toledo"
                        "https://github.com/carlostoledo1891"
                        "https://swell-floripa.vercel.app/"
                        "Luftrum"
                        "Porrumentzio"
                        "https://creativecommons.org/licenses/by/3.0/"
                        "https://github.com/marola-dev/marola/discussions/676"
                        "https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf" ] do
                      Expect.isTrue (has needle html) (Language.tag language + " " + needle)
          }
          test "support links Patreon and keeps the coming-soon channel disabled" {
              for language in Language.all do
                  let html = render "support" language
                  Expect.isTrue (has "href=\"https://www.patreon.com/maroladev\"" html) "patreon"
                  Expect.isTrue (has "<span aria-disabled=\"true\">Buy Me a Coffee <i>" html) "coffee"
          }
          test "a missing catalog key shows the key" {
              let bare =
                  { env with
                      Catalog = Map.ofList [ Language.PtBr, Map.empty; Language.En, Map.empty ] }

              match Site.render bare "about" Language.En with
              | Ok html -> Expect.isTrue (has ">nav.about</a>" html) "key"
              | Error e -> failwith e
          }
          test "the build lists pt-BR at the root and English under en/" {
              match Site.all env with
              | Ok files ->
                  Expect.equal
                      (files |> List.map fst |> List.sort)
                      [ "404.html"
                        "about.html"
                        "contact-sent.html"
                        "contact.html"
                        "en/404.html"
                        "en/about.html"
                        "en/contact-sent.html"
                        "en/contact.html"
                        "en/members.html"
                        "en/news.html"
                        "en/support.html"
                        "members.html"
                        "news.html"
                        "support.html" ]
                      "files"
              | Error e -> failwith e
          } ]
