/// What the page reads off the wire and off the browser, as values `Update` understands. The
/// decoders of the boards and areas live in `Marola`; these are the two files and the environment
/// that only the page reads.
module Marola.Client.App.Wire

open Thoth.Json.Core
open Marola
open Marola.Client

/// `data/<area>/latest.json`: the days that have a board, and each one's file.
let days: Decoder<DayEntry list> =
    Decode.field
        "days"
        (Decode.list (
            Decode.object (fun get ->
                { Date = get.Required.Field "day" Decode.string
                  File = get.Required.Field "file" Decode.string })
        ))

/// A board this page reads, or the schema number of one that it does not: a newer board is news
/// for the visitor, not a decode error.
let board: Decoder<Loaded> =
    Decode.field "schema" Decoders.int
    |> Decode.andThen (fun schema ->
        if List.contains schema Board.schemas then
            Board.decoder |> Decode.map Read
        else
            Decode.succeed (Newer schema))

let private envDecoder: Decoder<string * string * string list * bool> =
    Decode.object (fun get ->
        get.Required.Field "path" Decode.string,
        get.Required.Field "search" Decode.string,
        get.Required.Field "languages" (Decode.list Decode.string),
        get.Required.Field "reduced_motion" Decode.bool)

let parse (decoder: Decoder<'a>) (body: string) : Result<'a, FetchError> =
    Thoth.Json.JavaScript.Decode.fromString decoder body |> Result.mapError BadData

/// The browser's answer to `readEnv`. A text that does not decode gives the page at its root with
/// no preference, as the Lustre page did.
let env (text: string) (stored: string) : Env =
    let path, search, languages, reducedMotion =
        match Thoth.Json.JavaScript.Decode.fromString envDecoder text with
        | Ok found -> found
        | Error _ -> "/", "", [], false

    { Path = path
      Query = Params.parse search
      Languages = languages
      StoredLanguage = if stored = "" then None else Some stored
      ReducedMotion = reducedMotion }
