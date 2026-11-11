namespace Marola.Pages

open System
open System.Text.RegularExpressions
open Marola
open Marola.Client

/// One news post in one language, already rendered as its `<article>`.
type Post =
    {
        Date: string
        Slug: string
        Language: Language
        /// The `# ` line as written, for tests and logs.
        Title: string
        Minutes: int
        Article: Node<unit>
    }

/// The news posts of `site/content/news/`, the same format and the same rules as scripts/news_build.py:
/// a bad post is an error of the build, never a silently shorter page.
module News =

    let private name =
        Regex(@"^(\d{4})-(\d{2})-(\d{2})-([a-z0-9-]+)\.(pt-BR|en)\.md$", RegexOptions.Compiled)

    let private release =
        Regex(@"^::: release (v\d+\.\d+\.\d+) (\d{4})-(\d{2})-(\d{2})$", RegexOptions.Compiled)

    let releases = "https://github.com/marola-dev/marola/releases/tag/"

    // A common silent-reading rate for non-fiction; the minutes round up so a short post says 1.
    let private wordsPerMinute = 200

    let private months (language: Language) : string[] =
        match language with
        | Language.PtBr ->
            [| "janeiro"
               "fevereiro"
               "março"
               "abril"
               "maio"
               "junho"
               "julho"
               "agosto"
               "setembro"
               "outubro"
               "novembro"
               "dezembro" |]
        | Language.En ->
            [| "January"
               "February"
               "March"
               "April"
               "May"
               "June"
               "July"
               "August"
               "September"
               "October"
               "November"
               "December" |]

    let private readTime (language: Language) (minutes: int) : string =
        match language with
        | Language.PtBr -> string minutes + " min de leitura"
        | Language.En -> string minutes + " min read"

    let longDate (language: Language) (y: string) (mo: string) (d: string) : string =
        let month = (months language)[int mo - 1]

        match language with
        | Language.PtBr -> string (int d) + " de " + month + " de " + y
        | Language.En -> month + " " + string (int d) + ", " + y

    /// The words a reader reads: no link targets, no Markdown markup.
    let words (blocks: string list) : string list =
        let text =
            Regex.Replace(String.Join(" ", blocks), @"\]\([^)]*\)|^::: .*$", " ", RegexOptions.Multiline)

        Regex.Replace(text, @"[#*`\[\]]|^- ", " ")
        |> fun t -> Regex.Split(t.Trim(), @"\s+")
        |> Array.filter (fun w -> Regex.IsMatch(w, @"\w"))
        |> List.ofArray

    let readingMinutes (blocks: string list) : int =
        max 1 ((List.length (words blocks) + wordsPerMinute - 1) / wordsPerMinute)

    let private collapse (text: string) : string = Regex.Replace(text.Trim(), @"\s+", " ")

    // Markdown.inlineNodes plus the news rule that a leftover underscore is unrendered Markdown.
    let private inlineOf (text: string) : Result<Node<unit> list, string> =
        let rec visible (node: Node<unit>) : string =
            match node with
            | Text t -> t
            | El e -> String.Join("", e.Children |> List.map visible)

        Markdown.inlineNodes text
        |> Result.bind (fun nodes ->
            if (nodes |> List.map visible |> String.concat "").Contains '_' then
                Error("unsupported Markdown in: " + text)
            else
                Ok nodes)

    let private withInline (tag: string) (attrs: Attr<unit> list) (text: string) : Result<Node<unit>, string> =
        inlineOf text |> Result.map (Vdom.el tag attrs)

    /// `::: release vX.Y.Z YYYY-MM-DD`, then `- ` highlights, then one line of links.
    let private releaseCard (language: Language) (file: string) (block: string) : Result<Node<unit>, string> =
        let lines = block.Split '\n' |> List.ofArray
        let m = release.Match(List.head lines)

        if not m.Success || List.length lines < 2 then
            Error(file + ": '::: release vX.Y.Z YYYY-MM-DD' then its lines: " + List.head lines)
        else
            let items, links =
                List.tail lines |> List.partition (fun line -> line.StartsWith "- ")

            if List.isEmpty items || List.length links <> 1 then
                Error(file + ": a release card needs '- ' highlights and one line of links")
            else
                let tag, y, mo, d =
                    m.Groups[1].Value, m.Groups[2].Value, m.Groups[3].Value, m.Groups[4].Value

                items
                |> List.map (fun item -> withInline "li" [] (item.Substring 2))
                |> Markdown.collect
                |> Result.bind (fun lis ->
                    withInline "p" [ Vdom.cls "release-links" ] (List.head links)
                    |> Result.map (fun linkLine ->
                        Vdom.el
                            "aside"
                            [ Vdom.cls "release" ]
                            [ Vdom.el
                                  "p"
                                  [ Vdom.cls "release-head" ]
                                  [ Vdom.el
                                        "a"
                                        [ Vdom.cls "release-tag"; Vdom.attr "href" (releases + tag) ]
                                        [ Vdom.text ("marola " + tag) ]
                                    Vdom.text " "
                                    Vdom.el
                                        "time"
                                        [ Vdom.attr "datetime" (y + "-" + mo + "-" + d) ]
                                        [ Vdom.text (longDate language y mo d) ] ]
                              Vdom.el "ul" [] lis
                              linkLine ]))

    let private body (language: Language) (file: string) (block: string) : Result<Node<unit>, string> =
        if block.StartsWith "## " && not (block.Contains '\n') then
            withInline "h2" [] (block.Substring 3)
        elif block.StartsWith "### " && not (block.Contains '\n') then
            withInline "h3" [] (block.Substring 4)
        elif block.StartsWith "::: " then
            releaseCard language file block
        elif block.StartsWith "#" then
            Error(
                file
                + ": only ## and ### headings inside a post: "
                + block.Substring(0, min 40 block.Length)
            )
        elif block.StartsWith "- " then
            Regex.Split(block.Substring 2, "\n- ")
            |> List.ofArray
            |> List.map (fun item -> withInline "li" [] (collapse item))
            |> Markdown.collect
            |> Result.map (Vdom.el "ul" [])
        else
            withInline "p" [] (collapse block)

    /// One post file: its name decides the date, the slug and the language.
    let parse (file: string) (text: string) : Result<Post, string> =
        let m = name.Match file

        if not m.Success then
            Error(file + ": not YYYY-MM-DD-<slug>.<pt-BR|en>.md")
        else
            let y, mo, d, slug =
                m.Groups[1].Value, m.Groups[2].Value, m.Groups[3].Value, m.Groups[4].Value

            let language =
                if m.Groups[5].Value = "en" then
                    Language.En
                else
                    Language.PtBr

            let blocks =
                text.Replace("\r\n", "\n").Split "\n\n"
                |> Array.map (fun b -> b.Trim())
                |> Array.filter (fun b -> b <> "")
                |> List.ofArray

            match blocks with
            | title :: date :: lede :: rest when title.StartsWith "# " && not (title.Contains '\n') ->
                let iso = y + "-" + mo + "-" + d

                if date <> iso then
                    Error(file + ": the date line must be " + iso + ", the file's date")
                elif lede.StartsWith "#" || lede.StartsWith "- " then
                    Error(file + ": the paragraph after the date is the lede")
                else
                    let minutes = readingMinutes (title :: lede :: rest)

                    withInline "h2" [] (title.Substring 2)
                    |> Result.bind (fun heading ->
                        withInline "p" [ Vdom.cls "lede" ] (collapse lede)
                        |> Result.bind (fun ledeNode ->
                            rest
                            |> List.map (body language file)
                            |> Markdown.collect
                            |> Result.map (fun nodes ->
                                { Date = iso
                                  Slug = slug
                                  Language = language
                                  Title = title.Substring 2
                                  Minutes = minutes
                                  Article =
                                    Vdom.el
                                        "article"
                                        [ Vdom.cls "about-body"; Vdom.attr "lang" (Language.tag language) ]
                                        ([ heading
                                           Vdom.el
                                               "p"
                                               [ Vdom.cls "post-date" ]
                                               [ Vdom.el
                                                     "time"
                                                     [ Vdom.attr "datetime" iso ]
                                                     [ Vdom.text (longDate language y mo d) ]
                                                 Vdom.text (" · " + readTime language minutes) ]
                                           ledeNode ]
                                         @ nodes) })))
            | _ -> Error(file + ": needs a '# title', a date line and a lede")

    /// Every post of every language, or why the folder breaks the rules: no post, a post in one language
    /// only, a post the README index does not list.
    let build (files: (string * string) list) (index: string) : Result<Post list, string> =
        files
        |> List.map (fun (file, text) -> parse file text)
        |> Markdown.collect
        |> Result.bind (fun posts ->
            let keys (language: Language) =
                posts
                |> List.filter (fun p -> p.Language = language)
                |> List.map (fun p -> p.Date, p.Slug)
                |> Set.ofList

            let pt, en = keys Language.PtBr, keys Language.En

            if List.isEmpty posts then
                Error "news: no posts"
            else
                match Set.union (Set.difference pt en) (Set.difference en pt) |> Set.toList with
                | (d, s) :: _ -> Error(d + "-" + s + ": needs both a .pt-BR.md and an .en.md")
                | [] ->
                    match
                        pt
                        |> Set.toList
                        |> List.tryFind (fun (d, s) -> not (index.Contains(d + "-" + s)))
                    with
                    | Some(d, s) -> Error(d + "-" + s + ": not listed in news/README.md's index")
                    | None -> Ok posts)

    /// The posts of one language, newest first.
    let forLanguage (language: Language) (posts: Post list) : Post list =
        posts
        |> List.filter (fun p -> p.Language = language)
        |> List.sortWith (fun a b ->
            match String.CompareOrdinal(b.Date, a.Date) with
            | 0 -> String.CompareOrdinal(a.Slug, b.Slug)
            | c -> c)
