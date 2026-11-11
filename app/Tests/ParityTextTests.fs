/// The old ui.js and app.js text functions against golden.json.
module Marola.Tests.ParityTextTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Thoth.Json.Core
open Marola
open Marola.Tests.Support

let private why (section: string) (detail: string) : string = "golden " + section + ": " + detail

/// A node the way golden.json writes it: a string, `{hash: true}` or `{name, type?, cases?}`.
let private nodeDecoder: Decoder<IcuNode> =
    Decode.fix (fun self ->
        Decode.oneOf
            [ Decode.string |> Decode.map Literal
              Decode.field "hash" Decode.bool |> Decode.map (fun _ -> Hash)
              Decode.object (fun get ->
                  Argument(
                      get.Required.Field "name" Decode.string,
                      get.Optional.Field "type" Decode.string,
                      get.Optional.Field "cases" (Decode.dict (Decode.list self))
                      |> Option.defaultValue Map.empty
                  )) ])

let private parsedDecoder: Decoder<Result<IcuNode list, string>> =
    Decode.oneOf
        [ Decode.field "ok" (Decode.list nodeDecoder) |> Decode.map Ok
          Decode.field "error" Decode.string |> Decode.map Error ]

let tests =
    testList
        "parity text"
        [ testCase "band"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "score" Decoders.nullableInt,
                      get.Required.Field "unfit" Decode.bool,
                      get.Required.Field "out" Decode.string)

              for score, unfit, out in golden "band" entry do
                  Expect.equal (Band.cssClass (Band.ofScore score unfit)) out (why "band" (string (score, unfit)))

          testCase "number"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "n" Decoders.number,
                      get.Required.Field "min" Decoders.int,
                      get.Required.Field "max" Decoders.int,
                      get.Required.Field "out" Decode.string)

              for lang, n, min, max, out in golden "number" entry do
                  Expect.equal (NumFmt.fixedDigits n lang min max) out (why "number" (string (lang, n, min, max)))

          testCase "fmt"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "n" Decoders.nullableNumber,
                      get.Required.Field "unit" Decode.string,
                      get.Required.Field "digits" Decoders.nullableInt,
                      get.Required.Field "out" Decode.string)

              for lang, n, unit, digits, out in golden "fmt" entry do
                  // app.js defaults to one fraction digit when none is given.
                  Expect.equal
                      (Fmt.value (locale lang) n unit (Option.defaultValue 1 digits))
                      out
                      (why "fmt" (string (lang, n, unit, digits)))

          testCase "waves text"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "wave_m" Decoders.nullableNumber,
                      get.Required.Field "period_s" Decoders.nullableNumber,
                      get.Required.Field "out" Decode.string)

              for lang, m, s, out in golden "waves_text" entry do
                  Expect.equal (Fmt.waves (locale lang) m s) out (why "waves_text" (string (lang, m, s)))

          testCase "word"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "prefix" Decode.string,
                      get.Required.Field "value" Decode.string,
                      get.Required.Field "out" Decode.string)

              for lang, prefix, value, out in golden "word" entry do
                  Expect.equal (I18n.word (locale lang) prefix value) out (why "word" (string (lang, prefix, value)))

          testCase "compass"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "deg" Decoders.number,
                      get.Required.Field "out" Decode.string)

              for lang, deg, out in golden "compass" entry do
                  Expect.equal
                      (I18n.word (locale lang) "dir." (Geo.compassKey deg))
                      out
                      (why "compass" (string (lang, deg)))

          testCase "condition label"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "condition" Decode.string,
                      get.Required.Field "out" Decode.string)

              for lang, condition, out in golden "cond_label" entry do
                  Expect.equal
                      (Condition.label (Condition.parse condition) (locale lang))
                      out
                      (why "cond_label" condition)

          testCase "water summary and dot"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "water" Water.decoder,
                      get.Required.Field "summary" Decode.string,
                      get.Required.Field "dot" Decode.string)

              for lang, w, summary, dot in golden "water" entry do
                  Expect.equal (Water.summaryText w (locale lang)) summary (why "water" w.Summary)
                  Expect.equal (Water.dotClass w) dot (why "water dot" w.Summary)

          testCase "escape"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "in" Decode.string, get.Required.Field "out" Decode.string)

              for input, out in golden "esc" entry do
                  Expect.equal (Html.escapeHtml input) out (why "esc" input)

          testCase "lookup"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "key" Decode.string,
                      get.Required.Field "out" Decoders.nullableString)

              for lang, key, out in golden "lookup" entry do
                  Expect.equal (I18n.lookup (catalog ()) lang key) out (why "lookup" key)

          testCase "resolve language"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "param" Decoders.nullableString,
                      get.Required.Field "stored" Decoders.nullableString,
                      get.Required.Field "languages" (Decode.list Decode.string),
                      get.Required.Field "out" Decode.string)

              for param, stored, languages, out in golden "resolve_lang" entry do
                  let resolved = Language.resolve param stored languages Language.all
                  Expect.equal (Language.tag resolved) out (why "resolve_lang" (string (param, stored, languages)))

          testCase "icu parse"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "src" Decode.string, get.Required.Field "out" parsedDecoder)

              for src, expected in golden "icu_parse" entry do
                  Expect.equal (Icu.parse src) expected (why "icu_parse" src)

          testCase "icu format"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "src" Decode.string,
                      get.Required.Field "args" argsDecoder,
                      get.Required.Field "out" Decode.string)

              for lang, src, args, out in golden "icu_format" entry do
                  match Icu.parse src with
                  | Ok nodes ->
                      Expect.equal (Icu.format nodes args lang None) out (why "icu_format" (string (lang, src, args)))
                  | Error message -> failwith message

          testCase "t over the whole catalog"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "key" Decode.string,
                      get.Required.Field "out" Decode.string)

              for lang, key, out in golden "t_all" entry do
                  Expect.equal (I18n.t (locale lang) key []) out (why "t_all" (string (lang, key)))

          testCase "t with arguments"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "key" Decode.string,
                      get.Required.Field "args" argsDecoder,
                      get.Required.Field "out" Decode.string)

              for lang, key, args, out in golden "t" entry do
                  Expect.equal (I18n.t (locale lang) key args) out (why "t" (string (lang, key, args)))

          testCase "t falls back to the source language"
          <| fun () ->
              let byLanguage =
                  goldenOne
                      "fallback_catalog"
                      (Decode.keyValuePairs I18n.messagesDecoder
                       |> Decode.andThen (fun pairs ->
                           let languages =
                               pairs |> List.map (fun (tag, messages) -> Language.fromTag tag, messages)

                           if languages |> List.forall (fun (l, _) -> l.IsSome) then
                               Decode.succeed (languages |> List.map (fun (l, m) -> l.Value, m) |> Map.ofList)
                           else
                               Decode.fail "unknown language in fallback_catalog"))

              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "lang" langDecoder,
                      get.Required.Field "key" Decode.string,
                      get.Required.Field "args" argsDecoder,
                      get.Required.Field "out" Decode.string)

              for lang, key, args, out in golden "fallback" entry do
                  let loc =
                      { Catalog = byLanguage
                        Language = lang }

                  Expect.equal (I18n.t loc key args) out (why "fallback" (string (lang, key, args)))

          testCase "every catalog message parses"
          <| fun () ->
              for KeyValue(lang, messages) in catalog () do
                  for KeyValue(key, message) in messages do
                      match Icu.parse message with
                      | Ok _ -> ()
                      | Error _ -> failwith (Language.tag lang + " " + key + " does not parse") ]
