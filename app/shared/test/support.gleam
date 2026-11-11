//// Shared helpers of the tests: the files they read and the golden table.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string
import marola/beach.{type Beach}
import marola/decoders
import marola/i18n.{type Catalog, type Locale, Locale}
import marola/icu
import marola/language.{type Language}

@external(erlang, "marola_test_ffi", "read_file")
@external(javascript, "./marola_test_ffi.mjs", "read_file")
fn read_file(path: String) -> Result(String, String)

/// The tests run from `app/shared`.
pub fn read(path: String) -> String {
  case read_file(path) {
    Ok(text) -> text
    Error(reason) -> panic as { "cannot read " <> path <> ": " <> reason }
  }
}

pub fn parse_json(text: String, decoder: Decoder(a)) -> a {
  case json.parse(text, decoder) {
    Ok(value) -> value
    Error(error) -> panic as { "bad JSON: " <> string.inspect(error) }
  }
}

fn golden_data() -> Dynamic {
  parse_json(read("test/golden.json"), decode.dynamic)
}

/// One section of `golden.json`, each entry through `entry`.
pub fn golden(section: String, entry: Decoder(a)) -> List(a) {
  run(golden_data(), decode.at([section], decode.list(entry)), section)
}

pub fn golden_one(section: String, decoder: Decoder(a)) -> a {
  run(golden_data(), decode.at([section], decoder), section)
}

fn run(data: Dynamic, decoder: Decoder(a), what: String) -> a {
  case decode.run(data, decoder) {
    Ok(value) -> value
    Error(errors) ->
      panic as { "golden " <> what <> ": " <> string.inspect(errors) }
  }
}

pub fn lang(tag: String) -> Language {
  case language.from_tag(tag) {
    Ok(l) -> l
    Error(Nil) -> panic as { "unknown language " <> tag }
  }
}

pub fn lang_decoder() -> Decoder(Language) {
  decode.string |> decode.map(lang)
}

/// The real catalogs of the site.
pub fn catalog() -> Catalog {
  let messages = fn(tag) {
    parse_json(
      read("../../site/i18n/" <> tag <> ".json"),
      i18n.messages_decoder(),
    )
  }
  dict.from_list([
    #(language.PtBr, messages("pt-BR")),
    #(language.En, messages("en")),
  ])
}

pub fn locale(language: Language) -> Locale {
  Locale(catalog(), language)
}

/// The beaches the golden cases name.
pub fn variants() -> Dict(String, Beach) {
  golden_one("variants", decode.dict(decode.string, beach.decoder()))
}

pub fn beach_named(name: String) -> Beach {
  case dict.get(variants(), name) {
    Ok(b) -> b
    Error(Nil) -> panic as { "no golden beach " <> name }
  }
}

/// Message arguments as the golden file writes them: numbers and text.
pub fn args_decoder() -> Decoder(List(#(String, icu.Arg))) {
  let arg =
    decode.one_of(decoders.number() |> decode.map(icu.Num), [
      decode.string |> decode.map(icu.Text),
    ])
  decode.dict(decode.string, arg) |> decode.map(dict.to_list)
}

/// The slider position the golden cases write: no hour is the best hour.
pub fn selection(hour: Option(String)) -> beach.Selection {
  case hour {
    option.None -> beach.BestHour
    option.Some(h) -> beach.At(h)
  }
}

pub fn close(a: Float, b: Float, tolerance: Float) -> Bool {
  let scale = case a >. 1.0 || a <. -1.0 {
    True -> a
    False -> 1.0
  }
  let scale = case scale <. 0.0 {
    True -> 0.0 -. scale
    False -> scale
  }
  let diff = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  diff <=. tolerance *. scale
}

pub fn all_close(a: List(Float), b: List(Float), tolerance: Float) -> Bool {
  list.length(a) == list.length(b)
  && list.all(list.zip(a, b), fn(pair) { close(pair.0, pair.1, tolerance) })
}

/// A one-language catalog from key and message pairs.
pub fn catalog_of(messages: List(#(String, String))) -> Catalog {
  dict.from_list([#(language.En, dict.from_list(messages))])
}
