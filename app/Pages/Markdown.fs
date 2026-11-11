namespace Marola.Pages

open System.Text.RegularExpressions
open System
open System.Text
open Marola.Client

/// A page's text: its head fields and its body as nodes.
type Doc =
    { Title: string
      Description: string
      Body: Node<unit> list }

/// The small Markdown that the pages need, the same subset as scripts/news_build.py plus a few block
/// forms: `::lede`, `> ` quotes, `![alt](/src WxH)` figures and `{{soon name|label}}`. Anything else
/// that looks like markup is an error, so a page never goes out half-rendered. Text is escaped by
/// `Vdom.toHtml`, and a link may only go to `https:`, `http:` or a path on the site.
module Markdown =

    // A bare `about.html` is a sibling page: it resolves under `/` and under `/en/` to the page of the
    // same language, which the news posts rely on.
    let private sibling = Regex("^[a-z0-9-]+\\.html$", RegexOptions.Compiled)

    let private linkOk (url: string) : bool =
        (url.StartsWith "https://"
         || url.StartsWith "http://"
         || (url.StartsWith "/" && not (url.StartsWith "//"))
         || url.StartsWith "#"
         || sibling.IsMatch url)
        && not (url.Contains ' ')
        && not (url.Contains '"')

    /// Inline markup: `code`, **bold**, [text](url) and {{soon name|label}}.
    let inlineNodes (text: string) : Result<Node<unit> list, string> =
        let nodes = ResizeArray<Node<unit>>()
        let buf = StringBuilder()

        let flush () =
            if buf.Length > 0 then
                nodes.Add(Vdom.text (buf.ToString()))
                buf.Clear() |> ignore

        let find (needle: string) (from: int) =
            text.IndexOf(needle, from, StringComparison.Ordinal)

        let at (token: string) (i: int) =
            String.CompareOrdinal(text, i, token, 0, token.Length) = 0

        let mutable i = 0
        let mutable error: string option = None

        let fail (what: string) = error <- Some(what + ": " + text)

        while i < text.Length && error.IsNone do
            if at "`" i then
                match find "`" (i + 1) with
                | -1 -> fail "unclosed `"
                | j ->
                    flush ()
                    nodes.Add(Vdom.el "code" [] [ Vdom.text (text.Substring(i + 1, j - i - 1)) ])
                    i <- j + 1
            elif at "**" i then
                match find "**" (i + 2) with
                | -1 -> fail "unclosed **"
                | j ->
                    flush ()
                    nodes.Add(Vdom.el "b" [] [ Vdom.text (text.Substring(i + 2, j - i - 2)) ])
                    i <- j + 2
            elif at "[" i then
                match find "](" (i + 1) with
                | -1 -> fail "unclosed ["
                | j ->
                    match find ")" (j + 2) with
                    | -1 -> fail "unclosed ("
                    | k ->
                        let label = text.Substring(i + 1, j - i - 1)
                        let url = text.Substring(j + 2, k - j - 2)

                        if linkOk url && label <> "" && not (label.Contains '[') then
                            flush ()
                            nodes.Add(Vdom.el "a" [ Vdom.attr "href" url ] [ Vdom.text label ])
                            i <- k + 1
                        else
                            fail ("bad link " + url)
            elif at "{{soon " i then
                match find "}}" (i + 7) with
                | -1 -> fail "unclosed {{"
                | j ->
                    match text.Substring(i + 7, j - i - 7).Split '|' with
                    | [| name; label |] ->
                        flush ()

                        nodes.Add(
                            Vdom.el
                                "span"
                                [ Vdom.attr "aria-disabled" "true" ]
                                [ Vdom.text (name + " "); Vdom.el "i" [] [ Vdom.text label ] ]
                        )

                        i <- j + 2
                    | _ -> fail "{{soon name|label}}"
            elif at "*" i || at "]" i || at "{{" i then
                fail "unsupported markup"
            else
                buf.Append text[i] |> ignore
                i <- i + 1

        match error with
        | Some e -> Error e
        | None ->
            flush ()
            Ok(List.ofSeq nodes)

    let collect (items: Result<'a, string> list) : Result<'a list, string> =
        items
        |> List.fold
            (fun acc item ->
                match acc, item with
                | Ok xs, Ok x -> Ok(x :: xs)
                | Error e, _
                | _, Error e -> Error e)
            (Ok [])
        |> Result.map List.rev

    let private withInline (tag: string) (attrs: Attr<unit> list) (text: string) : Result<Node<unit>, string> =
        inlineNodes text |> Result.map (Vdom.el tag attrs)

    let private strip (prefix: string) (line: string) : string = line.Substring prefix.Length

    // `![alt](/src WxH)` then the caption lines.
    let private figure (lines: string list) : Result<Node<unit>, string> =
        let first = List.head lines

        match first.LastIndexOf "](" with
        | -1 -> Error("bad figure: " + first)
        | _ when not (first.EndsWith ")") -> Error("bad figure: " + first)
        | j ->
            let alt = first.Substring(2, j - 2)
            let spec = first.Substring(j + 2, first.Length - j - 3).Split ' '

            match spec with
            | [| src; size |] when linkOk src && size.Contains 'x' ->
                let w, h = size.Split('x').[0], size.Split('x').[1]

                inlineNodes (String.Join(" ", List.tail lines))
                |> Result.map (fun caption ->
                    Vdom.el
                        "figure"
                        []
                        [ Vdom.el
                              "a"
                              [ Vdom.attr "href" src ]
                              [ Vdom.el
                                    "img"
                                    [ Vdom.attr "src" src
                                      Vdom.attr "width" w
                                      Vdom.attr "height" h
                                      Vdom.attr "alt" alt ]
                                    [] ]
                          Vdom.el "figcaption" [] caption ])
            | _ -> Error("bad figure: " + first)

    // `> @en` sets the language of the quote, `> -- ` is the source line, other lines are paragraphs.
    let private quote (lines: string list) : Result<Node<unit>, string> =
        let lang, rest =
            match lines with
            | first :: tail when first.StartsWith "> @" -> [ Vdom.attr "lang" (strip "> @" first) ], tail
            | _ -> [], lines

        rest
        |> List.map (fun line ->
            if line.StartsWith "> -- " then
                withInline "footer" [] (strip "> -- " line)
            elif line.StartsWith "> " then
                withInline "p" [] (strip "> " line)
            else
                Error("bad quote line: " + line))
        |> collect
        |> Result.map (Vdom.el "blockquote" lang)

    let private block (lines: string list) : Result<Node<unit> option, string> =
        let first = List.head lines
        let some = Result.map Some

        if first.StartsWith "%% " then
            Ok None
        elif first.StartsWith "## " then
            some (withInline "h2" [] (strip "## " first))
        elif first.StartsWith "### " then
            some (withInline "h3" [] (strip "### " first))
        elif first.StartsWith "#" then
            Error("unsupported heading: " + first)
        elif first.StartsWith "- " then
            lines
            |> List.map (fun line ->
                if line.StartsWith "- " then
                    withInline "li" [] (strip "- " line)
                else
                    Error("a list item that wraps: " + line))
            |> collect
            |> Result.map (Vdom.el "ul" [])
            |> some
        elif first.StartsWith "> " then
            some (quote lines)
        elif first.StartsWith "![" then
            some (figure lines)
        elif first.StartsWith "::lede " then
            some (withInline "p" [ Vdom.cls "lede" ] (strip "::lede " (String.Join(" ", lines))))
        elif first.StartsWith "<" then
            Error("raw HTML is not supported: " + first)
        else
            some (withInline "p" [] (String.Join(" ", lines)))

    /// Blocks: groups of lines apart by a blank line.
    let private blocks (text: string) : string list list =
        text.Replace("\r\n", "\n").Split '\n'
        |> List.ofArray
        |> List.fold
            (fun (done', current) (line: string) ->
                if line.Trim() = "" then
                    (if List.isEmpty current then
                         done'
                     else
                         List.rev current :: done'),
                    []
                else
                    done', line.TrimEnd() :: current)
            ([], [])
        |> fun (done', current) ->
            List.rev (
                if List.isEmpty current then
                    done'
                else
                    List.rev current :: done'
            )

    /// `title:` and `description:` lines, a blank line, then the body.
    let parse (text: string) : Result<Doc, string> =
        match blocks text with
        | [] -> Error "empty page"
        | head :: body ->
            let field (name: string) =
                head
                |> List.tryPick (fun line ->
                    if line.StartsWith(name + ": ") then
                        Some(strip (name + ": ") line)
                    else
                        None)

            match field "title", field "description" with
            | Some title, Some description when List.length head = 2 ->
                body
                |> List.map block
                |> collect
                |> Result.map (fun nodes ->
                    { Title = title
                      Description = description
                      Body = List.choose id nodes })
            | _ -> Error "a page starts with the lines 'title: ' and 'description: '"
