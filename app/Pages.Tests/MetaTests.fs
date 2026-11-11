/// The cases of scripts/site_meta.py's self-test, plus the rules the F# build adds: both languages in the sitemap.
module Marola.Pages.Tests.MetaTests

open System
open System.Text.RegularExpressions
open System.Xml.Linq
open Expecto
open Marola
open Marola.Pages
open Marola.Pages.Tests.Support

let private base' = "https://marola.dev"
let private areas = env.Areas

let private sitemapLocs () : string list =
    let ns = XNamespace.Get "http://www.sitemaps.org/schemas/sitemap/0.9"

    XDocument.Parse(Meta.sitemap).Root.Elements(ns + "url")
    |> Seq.map (fun u -> (u.Element(ns + "loc")).Value)
    |> List.ofSeq

let tests =
    testList
        "meta"
        [ test "llms.txt opens with the H1 and the blockquote" {
              Expect.isTrue ((Meta.llms areas).StartsWith "# marola\n\n> ") "start"
          }
          test "llms.txt lists every area in site/areas.json" {
              Expect.isNonEmpty areas "areas"

              for area in areas do
                  Expect.stringContains (Meta.llms areas) (base' + "/data/" + area.Id + "/latest.json") area.Id
          }
          test "a new area appears with no edit" {
              Expect.stringContains
                  (Meta.llms (
                      areas
                      @ [ { Id = "recife"
                            Name = "Recife"
                            Lat = -8.05
                            Lon = -34.9 } ]
                  ))
                  (base' + "/data/recife/latest.json")
                  "recife"
          }
          test "llms.txt names every published page but the 404 and the thank-you page" {
              let listed =
                  Regex.Matches((Meta.llms areas), @"\(https://marola\.dev/([a-z-]+)\.html\)")
                  |> Seq.map (fun m -> m.Groups[1].Value)
                  |> Set.ofSeq

              let published =
                  Site.allSlugs
                  |> List.filter (fun s -> s <> "404" && s <> "contact-sent")
                  |> Set.ofList

              Expect.equal listed published "pages"
          }
          test "the sitemap parses and has every indexable page in both languages, the map once" {
              let locs = sitemapLocs ()
              let indexable = Site.allSlugs |> List.filter (Site.noIndex >> not)
              Expect.equal (List.length locs) (1 + 2 * (List.length indexable + List.length Meta.dynamicSlugs)) "count"
              Expect.isTrue (locs |> List.forall (fun u -> u.StartsWith(base' + "/"))) "origin"

              for slug in indexable do
                  for language in Language.all do
                      Expect.contains locs (base' + Layout.path language slug) (slug + " " + Language.tag language)
          }
          test "no noindex page is in the sitemap, in either language" {
              let locs = sitemapLocs ()

              for slug in Site.allSlugs |> List.filter Site.noIndex do
                  for language in Language.all do
                      Expect.isFalse (List.contains (base' + Layout.path language slug) locs) slug
          }
          test "each sitemap url names its alternates and x-default" {
              Expect.equal
                  (Regex.Matches(Meta.sitemap, "hreflang=\"pt-BR\"").Count)
                  (List.length (sitemapLocs ()))
                  "pt-BR"

              Expect.equal (Regex.Matches(Meta.sitemap, "hreflang=\"en\"").Count) (List.length (sitemapLocs ())) "en"

              Expect.equal
                  (Regex.Matches(Meta.sitemap, "hreflang=\"x-default\"").Count)
                  (List.length (sitemapLocs ()))
                  "x-default"
          }
          test "every sitemap page is a file the build writes" {
              match Site.all env with
              | Error e -> failwith e
              | Ok pages ->
                  let written = pages |> List.map fst |> Set.ofList

                  for loc in sitemapLocs () do
                      let path = loc.Substring(base'.Length)

                      if
                          path <> "/"
                          && not (Meta.dynamicSlugs |> List.exists (fun s -> path.EndsWith("/" + s)))
                      then
                          Expect.isTrue (written.Contains(path.TrimStart '/')) loc
          }
          test "Expires is under a year from the build" {
              let security = Meta.securityTxt (DateOnly(2026, 11, 11))
              Expect.stringContains security "Expires: 2027-11-10T00:00:00Z\n" "expires"
              Expect.isLessThan (DateOnly(2027, 11, 10).DayNumber - DateOnly(2026, 11, 11).DayNumber) 365 "days"
          }
          test "security.txt has the RFC 9116 fields" {
              let security = Meta.securityTxt (DateOnly(2026, 11, 11))

              for field in [ "Contact"; "Policy"; "Canonical" ] do
                  Expect.stringContains security ("\n" + field + ": ") field
          }
          test "the build writes the five metadata files" {
              match Meta.files env (DateOnly(2026, 11, 11)) with
              | Error e -> failwith e
              | Ok files ->
                  Expect.equal
                      (files |> List.map fst |> List.sort)
                      [ ".well-known/security.txt"
                        "humans.txt"
                        "llms.txt"
                        "robots.txt"
                        "sitemap.xml" ]
                      "files"
          }
          test "robots.txt allows all and points at the sitemap" {
              Expect.stringContains Meta.robots "User-agent: *\nAllow: /\n" "allow"
              Expect.stringContains Meta.robots ("Sitemap: " + base' + "/sitemap.xml") "sitemap"
          } ]
