/// The files the tests read: the repository's own catalogs and page Markdown.
module Marola.Pages.Tests.Support

open System
open System.IO
open System.Net
open System.Text.RegularExpressions
open Marola
open Marola.Pages

/// The nearest folder above the build output that holds the page content.
let root =
    let rec up (dir: DirectoryInfo) =
        if Directory.Exists(Path.Combine(dir.FullName, "site", "content", "pages")) then
            dir.FullName
        elif isNull dir.Parent then
            failwith "repository root not found"
        else
            up dir.Parent

    up (DirectoryInfo AppContext.BaseDirectory)

/// What the old static members page lists, the pt-BR article: name, affiliation, roles and links per member.
let oldMembersPage =
    File.ReadAllText(Path.Combine(root, "site/static/members.html"))

/// The repository keeps no copy of MEMBERS.md (marola-dev/.github has it), so the tests rebuild a table
/// from the members page that the old builder wrote from it: the same people, in the same order.
let membersTable: string =
    let article =
        let start = oldMembersPage.IndexOf "<article class=\"about-body\" lang=\"pt-BR\">"
        oldMembersPage.Substring(start, oldMembersPage.IndexOf("</article>", start) - start)

    let one (block: string) =
        let get (pattern: string) =
            let m = Regex.Match(block, pattern)

            if m.Success then
                WebUtility.HtmlDecode m.Groups[1].Value
            else
                ""

        let name = get "<span class=\"member-name\">([^<]*)</span>"
        let at = name.LastIndexOf ' '
        let role = get "<span class=\"member-role\">([^<]*)</span>"
        let marola = Regex.Match(role, "no marola: (.*?)( · no GitHub: (.*))?$")
        let orcid = get "ORCID ([0-9X-]+)</a>"
        let login = get "@([A-Za-z0-9-]+)</a>"

        let commit =
            Regex.Match(block, "<a href=\"([^\"]*)\">primeiro commit em ([0-9-]+)</a>")

        "| "
        + String.Join(
            " | ",
            [ name.Substring(at + 1) + ", " + name.Substring(0, at)
              get "<span class=\"member-aff\">([^<]*)</span>"
              (if orcid = "" then
                   ""
               else
                   "[" + orcid + "](https://orcid.org/" + orcid + ")")
              (if login = "" then
                   ""
               else
                   "[" + login + "](https://github.com/" + login + ")")
              (if commit.Success then
                   "[" + commit.Groups[2].Value + "](" + commit.Groups[1].Value + ")"
               else
                   "")
              marola.Groups[1].Value
              marola.Groups[3].Value ]
        )
        + " |"

    String.Join(
        "\n",
        [ "| " + String.Join(" | ", Members.header) + " |"
          "|---|---|---|---|---|---|---|"
          yield! Regex.Split(article, "<li class=\"member\">") |> Array.tail |> Array.map one ]
    )

let env: Env =
    match Loader.load (Path.Combine(root, "site")) membersTable with
    | Ok env -> env
    | Error message -> failwith message

let render (slug: string) (language: Language) : string =
    match Site.render env slug language with
    | Ok html -> html
    | Error message -> failwith message
