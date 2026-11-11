/// The board decoder against the fixtures and against boards that are wrong.
module Marola.Tests.BoardTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola
open Marola.Tests.Support

let private fixture = "site/fixtures/board.json"
let private fixtureV1 = "site/fixtures/board-schema1.json"

let private decode (text: string) : Result<Board, string> = parse Board.decoder text

let private decoded (text: string) : Board = parseOrFail Board.decoder text

let private isError (result: Result<'a, 'b>) : bool =
    match result with
    | Ok _ -> false
    | Error _ -> true

let private replace (a: string) (b: string) (text: string) : string = text.Replace(a, b)

let tests =
    testList
        "board"
        [ testCase "the schema 2 fixture decodes"
          <| fun () ->
              let b = decoded (read fixture)
              Expect.equal b.Schema 2 "schema"
              Expect.equal b.Area "fixture" "area"
              Expect.equal b.Lore None "lore"
              Expect.equal b.Sources.Water (Some "IMA/SC") "water source"

              Expect.equal (b.Beaches |> List.map (fun x -> x.Name)) [ "Praia da Joaquina"; "Praia Brava" ] "beaches"

              Expect.equal b.Trails [] "trails"
              Expect.equal (Board.hours b) [ "07:00"; "09:00"; "10:00"; "12:00"; "13:00" ] "hours"

              match b.Beaches with
              | [ joaquina; brava ] ->
                  Expect.equal joaquina.Best.Score 55 "best score"
                  Expect.equal (List.length joaquina.Best.NoteCodes) 2 "note codes"
                  let first = List.head joaquina.Best.NoteCodes
                  Expect.equal first.Code NoteCode.Breezy "first code"
                  Expect.equal (Map.tryFind "wind_kmh" first.Args) (Some(NoteArg.Number 27.0)) "arg"
                  Expect.isTrue brava.Water.Unfit "brava is unfit"

                  match brava.Water.Points with
                  | [ point ] ->
                      Expect.equal point.Condition Condition.Improper "condition"
                      Expect.equal point.EnterococciPer100ml (Some 800) "count"
                  | other -> failwithf "expected one point, got %d" (List.length other)

                  match brava.Hours with
                  | [ _; twelve ] ->
                      Expect.equal twelve.SeaTempC None "sea temp"
                      Expect.equal twelve.WindLevel None "wind level"
                  | other -> failwithf "expected two hours, got %d" (List.length other)
              | other -> failwithf "expected two beaches, got %d" (List.length other)

          testCase "the schema 1 fixture has no note codes"
          <| fun () ->
              let b = decoded (read fixtureV1)
              Expect.equal b.Schema 1 "schema"
              Expect.isTrue (b.Beaches |> List.forall (fun x -> List.isEmpty x.Best.NoteCodes)) "no codes"

          testCase "schema 3 is rejected"
          <| fun () ->
              let text = read fixture |> replace "\"schema\": 2" "\"schema\": 3"

              match decode text with
              | Ok _ -> failwith "schema 3 decoded"
              | Error message -> Expect.stringContains message "schema 1 or 2" "message"

          testCase "a board that is wrong is an error, not a crash"
          <| fun () ->
              let text = read fixture
              Expect.isTrue (isError (decode "{")) "truncated"
              Expect.isTrue (isError (decode "[]")) "list"
              Expect.isTrue (isError (decode (text |> replace "\"area\": \"fixture\"," ""))) "no area"
              Expect.isTrue (isError (decode (text |> replace "\"score\": 48" "\"score\": \"48\""))) "string score"
              Expect.isTrue (isError (decode (text |> replace "\"lat\": -27.6296" "\"lat\": null"))) "null lat"

          testCase "trails are optional and decode when present"
          <| fun () ->
              let trail =
                  "{\"name\": \"Trilha da Lagoinha\", \"length_km\": 2, \"difficulty\": \"mountain_hiking\", \"surface\": null, \"geometry\": [[-27.5, -48.4], [-27.51, -48.41]], \"near_beach\": {\"name\": \"Brava\", \"distance_km\": 0.3}, \"near_lake\": null}"

              let onePoint =
                  "{\"name\": \"Curta\", \"length_km\": 0.1, \"difficulty\": null, \"surface\": \"dirt\", \"geometry\": [[-27.5, -48.4]], \"near_beach\": null, \"near_lake\": null}"

              let text =
                  read fixture
                  |> replace "\"beaches\": [" ("\"trails\": [" + trail + "," + onePoint + "], \"beaches\": [")

              let b = decoded text

              match b.Trails with
              | [ long; short ] ->
                  Expect.equal long.Difficulty Difficulty.MountainHiking "difficulty"
                  Expect.equal long.LengthKm 2.0 "length"
                  Expect.equal long.NearBeach (Some { Name = "Brava"; DistanceKm = 0.3 }) "near beach"
                  Expect.equal long.NearLake None "near lake"
                  Expect.equal (List.length long.Geometry) 2 "points"
                  Expect.equal short.Difficulty Difficulty.Unrated "unrated"
                  Expect.equal (b.Trails |> List.filter Trail.drawable) [ long ] "drawable"
                  Expect.equal short.Surface (Some "dirt") "surface"
              | other -> failwithf "expected two trails, got %d" (List.length other)

          testCase "a value outside a closed set becomes unknown"
          <| fun () ->
              let text =
                  read fixture
                  |> replace "\"Low\"" "\"Extreme\""
                  |> replace "\"calm\"" "\"gale\""
                  |> replace "\"proper\"" "\"mystery\""
                  |> replace
                      "\"lore\": null"
                      "\"lore\": {\"kind\": \"poem\", \"text\": \"t\", \"source\": \"javascript:alert(1)\", \"lang\": \"en\"}"
                  |> replace "\"breezy\", \"args\"" "\"new_code\", \"args\""

              let b = decoded text
              let joaquina = List.head b.Beaches
              Expect.equal joaquina.Jellyfish (Level.Unknown "Extreme") "beach level"
              let first = List.head joaquina.Hours
              Expect.equal first.Jellyfish (Level.Unknown "Extreme") "hour level"
              Expect.equal first.WindLevel (Some(WindLevel.Unknown "gale")) "wind level"
              let point = List.head joaquina.Water.Points
              Expect.equal point.Condition (Condition.Unknown "mystery") "condition"

              Expect.equal
                  b.Lore
                  (Some
                      { Kind = LoreKind.Unknown "poem"
                        Text = "t"
                        Source = "javascript:alert(1)"
                        Lang = "en" })
                  "lore"

              let code = List.head joaquina.Best.NoteCodes
              Expect.equal code.Code (NoteCode.Unknown "new_code") "note code"

          testCase "note args of every shape decode"
          <| fun () ->
              let text =
                  read fixture
                  |> replace
                      "\"args\": {\"wind_kmh\": 27}"
                      "\"args\": {\"wind_kmh\": 27, \"place\": \"x\", \"avoid\": [\"a\", \"b\"], \"odd\": null, \"nested\": {\"a\": 1}}"

              let b = decoded text
              let first = b.Beaches |> List.head |> (fun x -> List.head x.Best.NoteCodes)
              Expect.equal (Map.tryFind "place" first.Args) (Some(NoteArg.Text "x")) "text"
              Expect.equal (Map.tryFind "avoid" first.Args) (Some(NoteArg.Places [ "a"; "b" ])) "places"
              Expect.equal (Map.tryFind "odd" first.Args) (Some NoteArg.Other) "null"
              Expect.equal (Map.tryFind "nested" first.Args) (Some NoteArg.Other) "object" ]
