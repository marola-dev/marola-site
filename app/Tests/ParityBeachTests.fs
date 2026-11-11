/// The old app.js beach functions against golden.json.
module Marola.Tests.ParityBeachTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Thoth.Json.Core
open Marola
open Marola.Tests.Support

let private why (section: string) (detail: string) : string = "golden " + section + ": " + detail

let private pointDecoder: Decoder<Point> =
    Decode.object (fun get ->
        { Lat = get.Required.Field "lat" Decoders.number
          Lon = get.Required.Field "lon" Decoders.number })

let private markDecoder: Decoder<(string * string option) option> =
    Decode.lossyOption (
        Decode.object (fun get ->
            get.Required.Field "cls" Decode.string, get.Required.Field "dot" Decoders.nullableString)
    )

let tests =
    testList
        "parity beach"
        [ testCase "haversine"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "a" pointDecoder,
                      get.Required.Field "b" pointDecoder,
                      get.Required.Field "km" Decoders.number)

              for a, b, km in golden "haversine" entry do
                  // sin and asin come from two different libms, so the last digits may differ
                  Expect.isTrue (close (Geo.haversineKm a b) km 1.0e-12) (why "haversine" (string (a, b)))

          testCase "shown and hourEntry"
          <| fun () ->
              let shownDecoder =
                  Decode.object (fun get ->
                      get.Required.Field "h" Decode.string,
                      get.Required.Field "score" Decoders.int,
                      get.Required.Field "notes" (Decode.list Decode.string),
                      get.Optional.Field "best" Decode.bool |> Option.defaultValue false)

              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "variant" Decode.string,
                      get.Required.Field "selection" Decoders.nullableString,
                      get.Required.Field "shown" (Decode.lossyOption shownDecoder),
                      get.Required.Field "entry_h" Decoders.nullableString)

              for variant, sel, expected, entryH in golden "shown" entry do
                  let b = beachNamed variant
                  let s = Beach.shown b (selection sel)
                  let got = s |> Option.map (fun s -> s.H, s.Score, s.Notes, s.Best)
                  Expect.equal got expected (why "shown" variant)
                  let e = Beach.hourEntry b s |> Option.map (fun e -> e.H)
                  Expect.equal e entryH (why "hour_entry" variant)

          testCase "aspects"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "variant" Decode.string,
                      get.Required.Field "selection" Decoders.nullableString,
                      get.Required.Field "head" Decode.string,
                      get.Required.Field "cells" (Decode.list Decode.string),
                      get.Required.Field "marks" (Decode.list markDecoder))

              for lang, variant, sel, head, cells, marks in golden "aspects" entry do
                  let b = beachNamed variant
                  let shown = Beach.shown b (selection sel)
                  let got = Aspects.ofBeach b shown (locale lang)
                  let label = string (lang, variant, sel)
                  Expect.equal got.Head head (why "aspects head" label)
                  Expect.equal (got.Cells |> List.map Aspects.cellText) cells (why "aspects cells" label)

                  // The water cell is the only one the old markup gave a class and a dot.
                  let quality =
                      marks
                      |> List.tryPick (fun m ->
                          match m with
                          | Some(cls, Some dot) -> Some(cls.Contains "unfit", dot)
                          | _ -> None)

                  let gotQuality =
                      got.Cells
                      |> List.tryPick (fun c ->
                          match c with
                          | Quality(_, unfit, dot) -> Some(unfit, dot)
                          | _ -> None)

                  Expect.equal gotQuality quality (why "aspects water cell" label)

          testCase "isPast"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "day" Decode.string,
                      get.Required.Field "today" Decode.string,
                      get.Required.Field "generated_at" Decode.string,
                      get.Required.Field "h" Decode.string,
                      get.Required.Field "out" Decode.bool)

              for day, today, generatedAt, h, out in golden "is_past" entry do
                  let b: Board =
                      { Schema = 2
                        Area = "x"
                        Day = day
                        Today = today
                        GeneratedAt = generatedAt
                        Sources =
                          { Beaches = ""
                            Forecast = ""
                            Water = None }
                        Lore = None
                        Beaches = []
                        Trails = [] }

                  Expect.equal (Board.isPast b h) out (why "is_past" (string (day, today, h)))

          testCase "ranked"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "variants" (Decode.list Decode.string),
                      get.Required.Field "hours" (Decode.list Decode.string),
                      get.Required.Field "index" (Decode.lossyOption Decoders.int),
                      get.Required.Field "here" (Decode.lossyOption pointDecoder),
                      get.Required.Field "names" (Decode.list Decode.string),
                      get.Required.Field "km" (Decode.lossyOption (Decode.list Decoders.number)))

              for variants, hours, index, here, names, km in golden "ranked" entry do
                  let beaches = variants |> List.map beachNamed

                  let sel =
                      match index with
                      | None -> Selection.BestHour
                      | Some i -> selection (List.tryItem i hours)

                  let label = string (index, here)

                  match here with
                  | None ->
                      let got = Rank.byScore beaches sel |> List.map (fun b -> b.Name)
                      Expect.equal got names (why "ranked by score" label)
                  | Some here ->
                      let got = Rank.byDistance beaches here
                      Expect.equal (got |> List.map (fun (b, _) -> b.Name)) names (why "ranked by distance" label)
                      let expectedKm = Option.get km
                      Expect.isTrue (allClose (got |> List.map snd) expectedKm 1.0e-12) (why "ranked km" label)

          testCase "ranking leaves the board alone"
          <| fun () ->
              let beaches = [ "joaquina"; "brava" ] |> List.map beachNamed
              Rank.byDistance beaches { Lat = -27.6; Lon = -48.48 } |> ignore
              Rank.byScore beaches Selection.BestHour |> ignore
              Expect.equal beaches ([ "joaquina"; "brava" ] |> List.map beachNamed) "unchanged"

              Expect.isTrue
                  (Water.hasNoData
                      { Summary = "no data"
                        Unfit = false
                        Note = None
                        Source = None
                        Points = [] })
                  "no data" ]
