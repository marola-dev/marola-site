//// The message catalog and `t()`: a port of ui.js `lookup` and `t`.

import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/option.{None}
import gleam/result
import gleam/string
import marola/icu.{type Arg}
import marola/language.{type Language}

/// The messages of each language, keyed by catalog key.
pub type Catalog =
  Dict(Language, Dict(String, String))

/// A catalog and the language the page shows now.
pub type Locale {
  Locale(catalog: Catalog, language: Language)
}

/// One language's file, `site/i18n/<tag>.json`.
pub fn messages_decoder() -> Decoder(Dict(String, String)) {
  decode.dict(decode.string, decode.string)
}

pub fn lookup(
  catalog: Catalog,
  language: Language,
  key: String,
) -> Result(String, Nil) {
  dict.get(catalog, language) |> result.try(dict.get(_, key))
}

/// The message for `key` in the language, else the source language's, else the
/// key itself. A message that does not parse also gives the key: the bundler
/// rejects those at build time, so showing the key beats a crash on the page.
pub fn t(loc: Locale, key: String, args: List(#(String, Arg))) -> String {
  let found = case lookup(loc.catalog, loc.language, key) {
    Ok(message) -> Ok(#(message, loc.language))
    Error(Nil) ->
      lookup(loc.catalog, language.source, key)
      |> result.map(fn(message) { #(message, language.source) })
  }
  case found {
    Error(Nil) -> key
    Ok(#(message, language)) ->
      case icu.parse(message) {
        Ok(nodes) -> icu.format(nodes, args, language, None)
        Error(_) -> key
      }
  }
}

/// A wire enum through the catalog (`wind.`, `lvl.`, `dir.`); a value with no
/// key passes through.
pub fn word(loc: Locale, prefix: String, value: String) -> String {
  let key = prefix <> string.lowercase(value)
  case t(loc, key, []) == key {
    True -> value
    False -> t(loc, key, [])
  }
}

/// `t` for the many calls that take one text argument.
pub fn arg(name: String, value: String) -> #(String, Arg) {
  #(name, icu.Text(value))
}

pub fn number_arg(name: String, value: Float) -> #(String, Arg) {
  #(name, icu.Num(value))
}
