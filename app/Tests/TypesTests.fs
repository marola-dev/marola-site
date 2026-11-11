/// The closed sets of the schema: each wire value has a case, and a value the page has not seen
/// is kept, not lost.
module Marola.Tests.TypesTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Thoth.Json.Core
open Marola
open Marola.Tests.Support

let private schema = "site/board.schema.json"

let private stringsAt (path: string list) : string list =
    parseOrFail (Decode.at path (Decode.list (Decode.lossyOption Decode.string))) (read schema)
    |> List.choose id

let private isError (result: Result<'a, 'b>) : bool =
    match result with
    | Ok _ -> false
    | Error _ -> true

let tests =
    testList
        "types"
        [ testCase "the 16 note codes of the schema are all known"
          <| fun () ->
              let codes =
                  stringsAt [ "$defs"; "note_codes"; "items"; "properties"; "code"; "enum" ]

              Expect.equal (List.length codes) 16 "16 codes"

              for code in codes do
                  let parsed = NoteCode.parse code
                  Expect.notEqual parsed (NoteCode.Unknown code) code
                  Expect.equal (NoteCode.toString parsed) code code

          testCase "the other closed sets of the schema are all known"
          <| fun () ->
              for value in stringsAt [ "$defs"; "likelihood"; "enum" ] do
                  Expect.notEqual (Level.parse value) (Level.Unknown value) value
                  Expect.equal (Level.toString (Level.parse value)) value value

              for value in stringsAt [ "properties"; "lore"; "properties"; "kind"; "enum" ] do
                  Expect.notEqual (Lore.parseKind value) (LoreKind.Unknown value) value

              let windPath =
                  [ "$defs"
                    "beach"
                    "properties"
                    "hours"
                    "items"
                    "properties"
                    "wind_level"
                    "enum" ]

              for value in stringsAt windPath do
                  Expect.notEqual (WindLevel.parse value) (WindLevel.Unknown value) value
                  Expect.equal (WindLevel.toString (WindLevel.parse value)) value value

          testCase "a water condition outside the set is kept"
          <| fun () ->
              Expect.equal (Condition.parse "proper") Condition.Proper "proper"
              Expect.equal (Condition.parse "improper") Condition.Improper "improper"
              Expect.equal (Condition.parse "unknown") Condition.Unclassified "unknown"
              Expect.equal (Condition.parse "closed") (Condition.Unknown "closed") "closed"

          testCase "a value the page has not seen is kept"
          <| fun () ->
              Expect.equal (Level.parse "Extreme") (Level.Unknown "Extreme") "level"
              Expect.equal (Level.parse "low") (Level.Unknown "low") "level is case sensitive"
              Expect.equal (WindLevel.parse "gale") (WindLevel.Unknown "gale") "wind"
              Expect.equal (Lore.parseKind "poem") (LoreKind.Unknown "poem") "lore"
              Expect.equal (NoteCode.parse "new_code") (NoteCode.Unknown "new_code") "code"
              Expect.equal (NoteCode.toString (NoteCode.Unknown "new_code")) "new_code" "code text"

              Expect.equal (Difficulty.parse (Some "alpine_hiking")) (Difficulty.Unknown "alpine_hiking") "difficulty"

          testCase "a trail difficulty picks the colour band"
          <| fun () ->
              Expect.equal (Difficulty.band (Difficulty.parse (Some "hiking"))) Band.Good "hiking"
              Expect.equal (Difficulty.band (Difficulty.parse (Some "mountain_hiking"))) Band.Fair "mountain"
              Expect.equal (Difficulty.band (Difficulty.parse (Some "alpine_hiking"))) Band.Unscored "unknown"
              Expect.equal (Difficulty.band (Difficulty.parse None)) Band.Unscored "none"
              Expect.equal (Difficulty.toString Difficulty.Hiking) (Some "hiking") "text"
              Expect.equal (Difficulty.toString Difficulty.Unrated) None "unrated"

          testCase "a non-string in a closed set is a decode error"
          <| fun () ->
              Expect.isTrue (isError (parse Level.decoder "5")) "number"
              Expect.isTrue (isError (parse WindLevel.decoder "null")) "null"
              Expect.equal (parse Level.decoder "\"Extreme\"") (Ok(Level.Unknown "Extreme")) "unknown"

          testCase "language tags"
          <| fun () ->
              Expect.equal (Language.fromTag "pt-BR") (Some Language.PtBr) "pt-BR"
              Expect.equal (Language.fromTag "en") (Some Language.En) "en"
              Expect.equal (Language.fromTag "fr") None "fr"
              Expect.equal (Language.fromTag "pt-br") None "case"
              Expect.equal (List.map Language.tag Language.all) [ "pt-BR"; "en" ] "all"
              Expect.equal (Language.matching (Some "pt") Language.all) (Some Language.PtBr) "primary subtag"
              Expect.equal (Language.matching (Some "en-GB") [ Language.PtBr ]) None "unsupported"

          testCase "water points and lore pick their classes"
          <| fun () ->
              Expect.equal (Band.cssClass (Condition.band Condition.Proper)) "c70" "proper"
              Expect.equal (Band.cssClass (Condition.band Condition.Improper)) "c0" "improper"
              Expect.equal (Band.cssClass (Condition.band Condition.Unclassified)) "cna" "unclassified"
              Expect.equal (Band.cssClass (Condition.band (Condition.Unknown "x"))) "cna" "unknown"
              Expect.equal (Lore.labelKey LoreKind.Creature) "lore.creature" "creature"
              Expect.equal (Lore.labelKey LoreKind.Secret) "lore.fact" "secret"
              Expect.equal (Lore.labelKey (LoreKind.Unknown "poem")) "lore.fact" "unknown kind"

          testCase "areas decode from a bare list and from the site file"
          <| fun () ->
              let expected =
                  [ { Id = "rio"
                      Name = "Rio de Janeiro"
                      Lat = -22.9
                      Lon = -43.2 } ]

              let bare =
                  "[{\"id\": \"rio\", \"name\": \"Rio de Janeiro\", \"lat\": -22.9, \"lon\": -43.2, \"radius_km\": 20}]"

              let wrapped = "{\"areas\": " + bare + "}"
              Expect.equal (parse Area.listDecoder bare) (Ok expected) "bare"
              Expect.equal (parse Area.listDecoder wrapped) (Ok expected) "wrapped"
              Expect.isTrue (isError (parse Area.listDecoder "{\"id\": \"rio\"}")) "one area"

              let noCentre = "[{\"id\": \"rio\", \"name\": \"Rio\", \"lat\": -22.9}]"
              Expect.isTrue (isError (parse Area.listDecoder noCentre)) "no centre" ]
