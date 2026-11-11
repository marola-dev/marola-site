namespace Marola

open Thoth.Json.Core

/// The messages of each language, keyed by catalog key.
type Catalog = Map<Language, Map<string, string>>

/// A catalog and the language the page shows now.
type Locale =
    { Catalog: Catalog; Language: Language }

/// The message catalog and `t()`: a port of ui.js `lookup` and `t`.
module I18n =

    /// One language's file, `site/i18n/<tag>.json`.
    let messagesDecoder: Decoder<Map<string, string>> = Decode.dict Decode.string

    let lookup (catalog: Catalog) (language: Language) (key: string) : string option =
        Map.tryFind language catalog |> Option.bind (Map.tryFind key)

    /// The message for `key` in the language, else the source language's, else the key itself. A
    /// message that does not parse also gives the key: the bundler rejects those at build time, so
    /// showing the key beats a crash on the page.
    let t (loc: Locale) (key: string) (args: (string * IcuArg) list) : string =
        let found =
            match lookup loc.Catalog loc.Language key with
            | Some message -> Some(message, loc.Language)
            | None ->
                lookup loc.Catalog Language.source key
                |> Option.map (fun m -> m, Language.source)

        match found with
        | None -> key
        | Some(message, language) ->
            match Icu.parse message with
            | Ok nodes -> Icu.format nodes args language None
            | Error _ -> key

    /// A wire enum through the catalog (`wind.`, `lvl.`, `dir.`); a value with no key passes through.
    let word (loc: Locale) (prefix: string) (value: string) : string =
        let key = prefix + value.ToLowerInvariant()
        let text = t loc key []
        if text = key then value else text

    /// `t` for the many calls that take one text argument.
    let arg (name: string) (value: string) : string * IcuArg = name, Text value

    let numberArg (name: string) (value: float) : string * IcuArg = name, Num value
