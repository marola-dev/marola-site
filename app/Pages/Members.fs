namespace Marola.Pages

open System
open System.Text.RegularExpressions
open Marola
open Marola.Client

/// One row of MEMBERS.md.
type Member =
    {
        /// `Given Family`, from Zenodo's `Family, Given`.
        Name: string
        Affiliation: string
        Orcid: string option
        GitHub: string option
        /// The date and the URL of the first commit.
        First: (string * string) option
        /// Empty under the old header, which has no role columns.
        MarolaRole: string
        GitHubRole: string
    }

/// The members page and humans.txt, from marola-dev/.github's MEMBERS.md: the same table, the same
/// rules and the same words as scripts/members_build.py. A row or a header that is wrong is an error
/// of the build, never a silent skip.
module Members =

    let header =
        [ "Name"
          "Affiliation"
          "ORCID"
          "GitHub"
          "First commit"
          "marola role"
          "GitHub role" ]

    // The header before the two role columns (MEMBERS.md, 14 October 2026): accepted until it moves.
    let legacy = List.truncate 5 header

    let zenodo = "https://doi.org/10.5281/zenodo.23224155"
    let file = "https://github.com/marola-dev/.github/blob/main/MEMBERS.md"

    /// The git blob id of a file's bytes: SHA-1 of "blob <length>\0" and the bytes, what `git hash-object` prints.
    let blobId (bytes: byte[]) : string =
        let head = Text.Encoding.ASCII.GetBytes("blob " + string bytes.Length + "\000")
        Convert.ToHexString(Security.Cryptography.SHA1.HashData(Array.append head bytes)).ToLowerInvariant()

    let private blobLine = Regex(@"^blob ([0-9a-f]{40})$", RegexOptions.Compiled)

    /// The blob id on the second line of site/members.version ("blob <sha>"), if the pin has one.
    let pinnedBlob (version: string) : string option =
        match version.Split '\n' |> Array.map (fun line -> line.Trim()) with
        | [||]
        | [| _ |] -> None
        | lines ->
            let m = blobLine.Match lines[1]
            if m.Success then Some m.Groups[1].Value else None

    /// The vendored MEMBERS.md as text, when its bytes are the blob the pin names. A copy that drifted from
    /// the pin is an error, never a silent switch to another source.
    let vendored (version: string) (bytes: byte[]) : Result<string, string> =
        match pinnedBlob version with
        | None -> Error "site/members.version has no second line 'blob <sha>' for site/members/MEMBERS.md"
        | Some pinned when blobId bytes <> pinned ->
            Error(
                "site/members/MEMBERS.md is blob "
                + blobId bytes
                + " but site/members.version pins "
                + pinned
            )
        | Some _ -> Ok(Text.Encoding.UTF8.GetString bytes)

    let private orcid =
        Regex(@"^\[([0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{3}[0-9X])\]\(https://orcid\.org/\1\)$", RegexOptions.Compiled)

    let private github =
        Regex(@"^\[([A-Za-z0-9-]{1,39})\]\(https://github\.com/\1\)$", RegexOptions.Compiled)

    let private commit =
        Regex(
            @"^\[([0-9]{4}-[0-9]{2}-[0-9]{2})\]\((https://github\.com/marola-dev/[A-Za-z0-9._-]+/commit/[0-9a-f]{40})\)$",
            RegexOptions.Compiled
        )

    let private row (full: bool) (cells: string list) : Result<Member, string> =
        let name, aff, orcidCell, gh, first =
            cells[0], cells[1], cells[2], cells[3], cells[4]

        if full && cells[5] = "" then
            Error(name + ": marola role is empty")
        else
            let at = name.IndexOf ", "

            if at < 1 || at + 2 >= name.Length then
                Error("Name is 'Family, Given', as Zenodo writes it: " + name)
            else
                let o = orcid.Match orcidCell
                let g = github.Match gh
                let c = commit.Match first

                if orcidCell <> "" && not o.Success then
                    Error(name + ": ORCID is [id](https://orcid.org/id) or empty: " + orcidCell)
                elif gh <> "" && not g.Success then
                    Error(name + ": GitHub is [login](https://github.com/login) or empty: " + gh)
                elif first <> "" && not c.Success then
                    Error(name + ": First commit is [YYYY-MM-DD](commit URL) or empty: " + first)
                else
                    Ok
                        { Name = name.Substring(at + 2) + " " + name.Substring(0, at)
                          Affiliation = aff
                          Orcid = if o.Success then Some o.Groups[1].Value else None
                          GitHub = if g.Success then Some g.Groups[1].Value else None
                          First =
                            if c.Success then
                                Some(c.Groups[1].Value, c.Groups[2].Value)
                            else
                                None
                          MarolaRole = if full then cells[5] else ""
                          GitHubRole = if full then cells[6] else "" }

    /// MEMBERS.md's table as members, in the file's order.
    let parse (text: string) : Result<Member list, string> =
        let cells =
            text.Split '\n'
            |> Array.map (fun line -> line.Trim())
            |> Array.filter (fun line -> line.StartsWith "|")
            |> Array.map (fun line -> line.Trim('|').Split '|' |> Array.map (fun c -> c.Trim()) |> List.ofArray)
            |> List.ofArray

        let wanted =
            "MEMBERS.md needs one table headed | " + String.Join(" | ", header) + " |"

        match cells with
        | head :: rule :: rows when
            (head = header || head = legacy)
            && rule |> List.forall (fun c -> c |> Seq.forall (fun ch -> "-: ".Contains ch))
            && not (List.isEmpty rows)
            ->
            let full = head = header

            rows
            |> List.map (fun cells ->
                if List.length cells <> List.length head then
                    Error(
                        "a row needs "
                        + string (List.length head)
                        + " cells: "
                        + String.Join(" | ", cells)
                    )
                else
                    row full cells)
            |> Markdown.collect
            |> Result.bind (fun members ->
                let firsts = members |> List.map (fun m -> m.First |> Option.map fst)
                let dated = firsts |> List.choose id

                if
                    dated <> List.sort dated
                    || List.truncate (List.length dated) firsts <> List.map Some dated
                then
                    Error "rows go by first commit, oldest first, then those with none"
                else
                    Ok members)
        | _ -> Error wanted

    let initials (name: string) : string =
        let parts = name.Split([| ' '; '\t' |], StringSplitOptions.RemoveEmptyEntries)
        (parts[0].Substring(0, 1) + (Array.last parts).Substring(0, 1)).ToUpperInvariant()

    /// The avatar file of each login must be in the folder, and no other: the page never asks GitHub.
    let checkAvatars (avatars: Map<string, string>) (members: Member list) : Result<unit, string> =
        let logins = members |> List.choose _.GitHub |> Set.ofList
        let have = avatars |> Map.keys |> Set.ofSeq

        if logins = have then
            Ok()
        else
            Error(
                "img/members/ has avatars for "
                + String.Join(", ", have)
                + ", MEMBERS.md lists "
                + String.Join(", ", logins)
                + ": run scripts/members_build.py"
            )

    type private Copy =
        { Title: string
          Lede: Node<unit> list
          Commit: string -> string
          Role: string -> string
          GitHubRole: string -> string
          Foot: Node<unit> list }

    let private a (href: string) (children: Node<unit> list) : Node<unit> =
        Vdom.el "a" [ Vdom.attr "href" href ] children

    let private copy (language: Language) : Copy =
        let t = Vdom.text

        match language with
        | Language.PtBr ->
            { Title = "membros"
              Lede =
                [ t
                      "as pessoas que fazem o marola, na ordem do primeiro commit de cada uma nos repositórios do projeto. quem tem ORCID também é autor do "
                  a zenodo [ t "registro do marola no Zenodo" ]
                  t "." ]
              Commit = fun d -> "primeiro commit em " + d
              Role = fun r -> "no marola: " + r
              GitHubRole = fun r -> "no GitHub: " + r
              Foot =
                [ t "a lista vem do arquivo "
                  a file [ Vdom.el "code" [] [ t "MEMBERS.md" ] ]
                  t
                      " da organização no GitHub. para entrar na lista ou corrigir seus dados, abra um pull request nesse arquivo." ] }
        | Language.En ->
            { Title = "Members"
              Lede =
                [ t
                      "The people who build marola, in the order of their first commit to the project's repositories. Those with an ORCID are also creators of the "
                  a zenodo [ t "marola record on Zenodo" ]
                  t "." ]
              Commit = fun d -> "first commit on " + d
              Role = fun r -> "marola: " + r
              GitHubRole = fun r -> "GitHub: " + r
              Foot =
                [ t "The list comes from the organization's "
                  a file [ Vdom.el "code" [] [ t "MEMBERS.md" ] ]
                  t " on GitHub. To join it or fix your details, open a pull request on that file." ] }

    let private span (cls: string) (children: Node<unit> list) : Node<unit> =
        Vdom.el "span" [ Vdom.cls cls ] children

    let private item (c: Copy) (avatars: Map<string, string>) (m: Member) : Node<unit> =
        let mark =
            match m.GitHub |> Option.bind (fun login -> Map.tryFind login avatars) with
            | Some name ->
                // Absolute, so /en/members.html reaches the same files as /members.html.
                Vdom.el
                    "img"
                    [ Vdom.cls "member-mark"
                      Vdom.attr "src" ("/img/members/" + name)
                      Vdom.attr "width" "48"
                      Vdom.attr "height" "48"
                      Vdom.attr "alt" ""
                      Vdom.attr "loading" "lazy" ]
                    []
            | None ->
                Vdom.el
                    "span"
                    [ Vdom.cls "member-mark"; Vdom.attr "aria-hidden" "true" ]
                    [ Vdom.text (initials m.Name) ]

        let links =
            [ m.Orcid
              |> Option.map (fun id -> a ("https://orcid.org/" + id) [ Vdom.text ("ORCID " + id) ])
              m.GitHub
              |> Option.map (fun login -> a ("https://github.com/" + login) [ Vdom.text ("@" + login) ])
              m.First |> Option.map (fun (date, url) -> a url [ Vdom.text (c.Commit date) ]) ]
            |> List.choose id
            |> List.indexed
            |> List.collect (fun (i, link) -> if i = 0 then [ link ] else [ Vdom.text " "; link ])

        // The roles are MEMBERS.md's words, shown as they are written there.
        let roles =
            [ if m.MarolaRole <> "" then
                  c.Role m.MarolaRole
              if m.GitHubRole <> "" then
                  c.GitHubRole m.GitHubRole ]

        Vdom.el
            "li"
            [ Vdom.cls "member" ]
            ([ mark; span "member-name" [ Vdom.text m.Name ] ]
             @ (if m.Affiliation <> "" then
                    [ span "member-aff" [ Vdom.text m.Affiliation ] ]
                else
                    [])
             @ (if List.isEmpty roles then
                    []
                else
                    [ span "member-role" [ Vdom.text (String.Join(" · ", roles)) ] ])
             @ (if List.isEmpty links then
                    []
                else
                    [ span "member-links" links ]))

    /// The `<article>` of the page in one language.
    let article (language: Language) (avatars: Map<string, string>) (members: Member list) : Node<unit> =
        let c = copy language

        Vdom.el
            "article"
            [ Vdom.cls "about-body"; Vdom.attr "lang" (Language.tag language) ]
            [ Vdom.el "h2" [] [ Vdom.text c.Title ]
              Vdom.el "p" [ Vdom.cls "lede" ] c.Lede
              Vdom.el "ul" [ Vdom.cls "members" ] (members |> List.map (item c avatars))
              Vdom.el "p" [] c.Foot ]

    /// humanstxt.org's plain format, one block per member in MEMBERS.md's order.
    let humans (members: Member list) : string =
        let lines =
            [ yield "/* TEAM */"
              yield "# Generated by app/Pages.Build from marola-dev/.github's MEMBERS.md; do not edit."
              yield ""

              for m in members do
                  yield "Name: " + m.Name

                  if m.MarolaRole <> "" then
                      yield "Role: " + m.MarolaRole

                  if m.Affiliation <> "" then
                      yield "Affiliation: " + m.Affiliation

                  match m.GitHub with
                  | Some login -> yield "GitHub: https://github.com/" + login
                  | None -> ()

                  match m.Orcid with
                  | Some id -> yield "ORCID: https://orcid.org/" + id
                  | None -> ()

                  yield ""

              yield "/* SITE */"
              yield "Members: " + file
              yield "Cite: " + zenodo
              yield "Code: https://github.com/marola-dev/marola-site"
              yield "Language: Português (Brasil), English"
              yield "Standards: HTML, CSS, F# compiled to JavaScript; no framework"
              yield "Components: MapLibre GL JS, Inter" ]

        String.Join("\n", lines) + "\n"
