namespace Marola

/// One piece of a parsed message.
type IcuNode =
    | Literal of string
    | Hash
    | Argument of name: string * kind: string option * cases: Map<string, IcuNode list>

/// A message argument: a number prints in the language's format, text as is.
type IcuArg =
    | Num of float
    | Text of string

/// The ICU message subset the catalogs use: `{arg}`, `{n, plural, ...}` with `#`, and
/// `{x, select, ...}`. A port of ui.js `parse` and `format`.
module Icu =

    /// The cursor is a position in the source. Positions in errors count UTF-16 units, as ui.js
    /// does.
    type private Cursor = { Source: string; Pos: int }

    let private at (cursor: Cursor) : char option =
        if cursor.Pos < cursor.Source.Length then
            Some cursor.Source.[cursor.Pos]
        else
            None

    let private advance (cursor: Cursor) : Cursor =
        if cursor.Pos < cursor.Source.Length then
            { cursor with Pos = cursor.Pos + 1 }
        else
            cursor

    let private fail (cursor: Cursor) (expected: string) : Result<'a, string> =
        Error(
            "i18n: expected "
            + expected
            + " at "
            + string cursor.Pos
            + " in "
            + cursor.Source
        )

    /// JavaScript's `\s`.
    let private isSpace (c: char) : bool =
        match c with
        | ' '
        | '\t'
        | '\n'
        | '\r'
        | '\u000B'
        | '\u000C'
        | '\u00A0'
        | '\u1680'
        | '\u2028'
        | '\u2029'
        | '\u202F'
        | '\u205F'
        | '\u3000'
        | '\uFEFF' -> true
        | _ -> c >= '\u2000' && c <= '\u200A'

    let rec private skipSpaces (cursor: Cursor) : Cursor =
        match at cursor with
        | Some c when isSpace c -> skipSpaces (advance cursor)
        | _ -> cursor

    let private takeName (cursor: Cursor) : string * Cursor =
        let mutable pos = cursor.Pos
        let source = cursor.Source

        while pos < source.Length
              && not (
                  isSpace source.[pos]
                  || source.[pos] = ','
                  || source.[pos] = '{'
                  || source.[pos] = '}'
              ) do
            pos <- pos + 1

        source.Substring(cursor.Pos, pos - cursor.Pos), { cursor with Pos = pos }

    let private word (cursor: Cursor) : Result<string * Cursor, string> =
        let name, after = takeName (skipSpaces cursor)

        if name = "" then
            fail cursor "a name"
        else
            Ok(name, skipSpaces after)

    let private expect (cursor: Cursor) (char: char) : Result<Cursor, string> =
        match at cursor with
        | Some c when c = char -> Ok(advance cursor)
        | _ -> fail cursor (string char)

    let private flush (out: IcuNode list) (text: char list) : IcuNode list =
        match text with
        | [] -> out
        | _ -> Literal(text |> List.rev |> Array.ofList |> System.String) :: out

    let rec private message (cursor: Cursor) (inPlural: bool) : Result<IcuNode list * Cursor, string> =
        let rec loop cursor (out: IcuNode list) (text: char list) =
            match at cursor with
            | None
            | Some '}' -> Ok(List.rev (flush out text), cursor)
            | Some '{' ->
                argument (advance cursor) inPlural
                |> Result.bind (fun (node, after) -> loop after (node :: flush out text) [])
            | Some '#' when inPlural -> loop (advance cursor) (Hash :: flush out text) []
            | Some c -> loop (advance cursor) out (c :: text)

        loop cursor [] []

    and private argument (cursor: Cursor) (inPlural: bool) : Result<IcuNode * Cursor, string> =
        word cursor
        |> Result.bind (fun (name, cursor) ->
            match at cursor with
            | Some ',' ->
                word (advance cursor)
                |> Result.bind (fun (kind, cursor) ->
                    expect cursor ','
                    |> Result.bind (fun cursor ->
                        cases (skipSpaces cursor) (inPlural || kind = "plural") Map.empty
                        |> Result.bind (fun (cases, cursor) ->
                            expect cursor '}'
                            |> Result.map (fun cursor -> Argument(name, Some kind, cases), cursor))))
            | _ ->
                expect cursor '}'
                |> Result.map (fun cursor -> Argument(name, None, Map.empty), cursor))

    and private cases
        (cursor: Cursor)
        (inPlural: bool)
        (acc: Map<string, IcuNode list>)
        : Result<Map<string, IcuNode list> * Cursor, string> =
        match at cursor with
        | None
        | Some '}' -> Ok(acc, cursor)
        | _ ->
            word cursor
            |> Result.bind (fun (key, cursor) ->
                expect cursor '{'
                |> Result.bind (fun cursor ->
                    message cursor inPlural
                    |> Result.bind (fun (nodes, cursor) ->
                        expect cursor '}'
                        |> Result.bind (fun cursor -> cases (skipSpaces cursor) inPlural (Map.add key nodes acc)))))

    let parse (source: string) : Result<IcuNode list, string> =
        message { Source = source; Pos = 0 } false
        |> Result.bind (fun (nodes, cursor) ->
            if cursor.Pos >= source.Length then
                Ok nodes
            else
                Error("i18n: unbalanced } in " + source))

    /// The number an argument stands for, if it is one.
    let private numberOf (value: IcuArg option) : float option =
        match value with
        | Some(Num f) -> Some f
        | Some(Text s) -> Parse.tryFloat s
        | None -> None

    /// A case key for a value: JavaScript's `String(v)`.
    let private key (value: IcuArg option) : string =
        match value with
        | Some(Num f) ->
            if f = System.Math.Truncate f && abs f < 1e15 then
                string (int64 f)
            else
                Parse.shortest f
        | Some(Text s) -> s
        | None -> "undefined"

    /// CLDR 42+: a whole multiple of a million takes "many".
    let private ptManyOrOther (n: float) : string =
        if n = System.Math.Truncate n && n % 1000000.0 = 0.0 then
            "many"
        else
            "other"

    /// CLDR plural category for the catalogs' two languages; text that is not a number selects
    /// "other", as Intl does with NaN.
    let private pluralCategory (language: Language) (value: IcuArg option) : string =
        match numberOf value with
        | None -> "other"
        | Some f ->
            let n = abs f

            match language with
            | Language.En -> if n = 1.0 then "one" else "other"
            | Language.PtBr -> if n < 2.0 then "one" else ptManyOrOther n

    /// The first of `keys` the message has, else its `other` case.
    let private firstCase (cases: Map<string, IcuNode list>) (keys: string list) : IcuNode list =
        match keys |> List.tryPick (fun k -> Map.tryFind k cases) with
        | Some nodes -> nodes
        | None -> Map.tryFind "other" cases |> Option.defaultValue []

    /// What `#` prints: Intl formats the number, and NaN for what is not one.
    let private hashText (value: IcuArg option) (language: Language) : string =
        match numberOf value with
        | Some f -> NumFmt.format f language
        | None -> "NaN"

    /// ui.js `format`: `n` is the plural number that `#` prints.
    let rec format
        (nodes: IcuNode list)
        (args: (string * IcuArg) list)
        (language: Language)
        (n: IcuArg option)
        : string =
        nodes
        |> List.map (fun node ->
            match node with
            | Literal text -> text
            | Hash -> hashText n language
            | Argument(name, None, _) ->
                match List.tryFind (fun (k, _) -> k = name) args with
                | None -> "{" + name + "}"
                | Some(_, Num f) -> NumFmt.format f language
                | Some(_, Text s) -> s
            | Argument(name, Some "plural", cases) ->
                let v = List.tryFind (fun (k, _) -> k = name) args |> Option.map snd
                let chosen = firstCase cases [ "=" + key v; pluralCategory language v ]
                format chosen args language v
            | Argument(name, Some _, cases) ->
                let v = List.tryFind (fun (k, _) -> k = name) args |> Option.map snd
                format (firstCase cases [ key v ]) args language n)
        |> String.concat ""
