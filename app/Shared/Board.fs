namespace Marola

open Thoth.Json.Core

type Sources =
    { Beaches: string
      Forecast: string
      Water: string option }

/// One area, one day: every nearby beach with every daylight hour scored (MIP-0005 section 5.2).
/// The decoder follows `site/board.schema.json`.
type Board =
    { Schema: int
      Area: string
      Day: string
      Today: string
      GeneratedAt: string
      Sources: Sources
      Lore: Lore option
      Beaches: Beach list
      Trails: Trail list }

module Board =

    /// The schemas this page reads; 2 adds note codes. A later one is a board newer than the page.
    let schemas = [ 1; 2 ]

    let private sourcesDecoder: Decoder<Sources> =
        Decode.object (fun get ->
            { Beaches = get.Required.Field "beaches" Decode.string
              Forecast = get.Required.Field "forecast" Decode.string
              Water = get.Required.Field "water" Decoders.nullableString })

    let private body (schema: int) : Decoder<Board> =
        Decode.object (fun get ->
            { Schema = schema
              Area = get.Required.Field "area" Decode.string
              Day = get.Required.Field "day" Decode.string
              Today = get.Required.Field "today" Decode.string
              GeneratedAt = get.Required.Field "generated_at" Decode.string
              Sources = get.Required.Field "sources" sourcesDecoder
              Lore = get.Required.Field "lore" (Decode.lossyOption Lore.decoder)
              Beaches = get.Required.Field "beaches" (Decode.list Beach.decoder)
              Trails =
                get.Optional.Field "trails" (Decode.list Trail.decoder)
                |> Option.defaultValue [] })

    let private schemasText = schemas |> List.map string |> String.concat " or "

    let decoder: Decoder<Board> =
        Decode.field "schema" Decoders.int
        |> Decode.andThen (fun schema ->
            if List.contains schema schemas then
                body schema
            else
                Decode.fail ("Expecting schema " + schemasText + " but got " + string schema))

    /// The union of the beaches' hours, sorted: the slider's stops.
    let hours (board: Board) : string list =
        board.Beaches
        |> List.collect (fun b -> b.Hours |> List.map (fun (h: Hour) -> h.H))
        |> List.distinct
        |> List.sortWith (fun a b -> System.String.CompareOrdinal(a, b))

    /// The characters of `text` from `start`, at most `length`; short text gives what is there.
    let private slice (text: string) (start: int) (length: int) : string =
        if text.Length <= start then
            ""
        else
            text.Substring(start, min length (text.Length - start))

    /// Whether `h` has passed: only on the day the board was made, and only against the generation time.
    let isPast (board: Board) (h: string) : bool =
        board.Day = board.Today
        && System.String.CompareOrdinal(h, slice board.GeneratedAt 11 5) < 0
