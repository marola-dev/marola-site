//// The old ui.js and app.js text functions against golden.json.

import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import marola/band
import marola/decoders
import marola/fmt
import marola/geo
import marola/html
import marola/i18n.{Locale}
import marola/icu.{type Node}
import marola/language
import marola/numfmt
import marola/water
import support

fn why(section: String, detail: String) -> String {
  "golden " <> section <> ": " <> detail
}

pub fn band_test() {
  let entry = {
    use score <- decode.field("score", decode.optional(decode.int))
    use unfit <- decode.field("unfit", decode.bool)
    use out <- decode.field("out", decode.string)
    decode.success(#(score, unfit, out))
  }
  use #(score, unfit, out) <- list.each(support.golden("band", entry))
  assert band.css_class(band.of_score(score, unfit)) == out
    as why("band", string.inspect(#(score, unfit)))
}

pub fn number_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use n <- decode.field("n", decoders.number())
    use min <- decode.field("min", decode.int)
    use max <- decode.field("max", decode.int)
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, n, min, max, out))
  }
  use #(lang, n, min, max, out) <- list.each(support.golden("number", entry))
  assert numfmt.fixed(n, lang, min, max) == out
    as why("number", string.inspect(#(lang, n, min, max)))
}

pub fn fmt_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use n <- decode.field("n", decoders.nullable_number())
    use unit <- decode.field("unit", decode.string)
    use digits <- decode.field("digits", decode.optional(decode.int))
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, n, unit, digits, out))
  }
  use #(lang, n, unit, digits, out) <- list.each(support.golden("fmt", entry))
  // app.js defaults to one fraction digit when none is given.
  assert fmt.value(support.locale(lang), n, unit, option.unwrap(digits, 1))
    == out
    as why("fmt", string.inspect(#(lang, n, unit, digits)))
}

pub fn waves_text_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use m <- decode.field("wave_m", decoders.nullable_number())
    use s <- decode.field("period_s", decoders.nullable_number())
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, m, s, out))
  }
  use #(lang, m, s, out) <- list.each(support.golden("waves_text", entry))
  assert fmt.waves(support.locale(lang), m, s) == out
    as why("waves_text", string.inspect(#(lang, m, s)))
}

pub fn word_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use prefix <- decode.field("prefix", decode.string)
    use value <- decode.field("value", decode.string)
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, prefix, value, out))
  }
  use #(lang, prefix, value, out) <- list.each(support.golden("word", entry))
  assert i18n.word(support.locale(lang), prefix, value) == out
    as why("word", string.inspect(#(lang, prefix, value)))
}

pub fn compass_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use deg <- decode.field("deg", decoders.number())
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, deg, out))
  }
  use #(lang, deg, out) <- list.each(support.golden("compass", entry))
  assert i18n.word(support.locale(lang), "dir.", geo.compass_key(deg)) == out
    as why("compass", string.inspect(#(lang, deg)))
}

pub fn condition_label_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use condition <- decode.field("condition", decode.string)
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, condition, out))
  }
  use #(lang, condition, out) <- list.each(support.golden("cond_label", entry))
  let label =
    water.condition_label(
      water.parse_condition(condition),
      support.locale(lang),
    )
  assert label == out as why("cond_label", condition)
}

pub fn water_summary_and_dot_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use w <- decode.field("water", water.decoder())
    use summary <- decode.field("summary", decode.string)
    use dot <- decode.field("dot", decode.string)
    decode.success(#(lang, w, summary, dot))
  }
  use #(lang, w, summary, dot) <- list.each(support.golden("water", entry))
  assert water.summary_text(w, support.locale(lang)) == summary
    as why("water", w.summary)
  assert water.dot_class(w) == dot as why("water dot", w.summary)
}

pub fn escape_test() {
  let entry = {
    use input <- decode.field("in", decode.string)
    use out <- decode.field("out", decode.string)
    decode.success(#(input, out))
  }
  use #(input, out) <- list.each(support.golden("esc", entry))
  assert html.escape_html(input) == out as why("esc", input)
}

pub fn lookup_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use key <- decode.field("key", decode.string)
    use out <- decode.field("out", decode.optional(decode.string))
    decode.success(#(lang, key, out))
  }
  use #(lang, key, out) <- list.each(support.golden("lookup", entry))
  let found = case i18n.lookup(support.catalog(), lang, key) {
    Ok(message) -> Some(message)
    Error(Nil) -> None
  }
  assert found == out as why("lookup", key)
}

pub fn resolve_language_test() {
  let entry = {
    use param <- decode.field("param", decode.optional(decode.string))
    use stored <- decode.field("stored", decode.optional(decode.string))
    use languages <- decode.field("languages", decode.list(decode.string))
    use out <- decode.field("out", decode.string)
    decode.success(#(param, stored, languages, out))
  }
  use #(param, stored, languages, out) <- list.each(support.golden(
    "resolve_lang",
    entry,
  ))
  let resolved = language.resolve(param, stored, languages, language.all)
  assert language.tag(resolved) == out
    as why("resolve_lang", string.inspect(#(param, stored, languages)))
}

// --- the ICU subset ---

type Parsed {
  Parsed(nodes: List(Node))
  Failed(message: String)
}

fn node_decoder() -> decode.Decoder(Node) {
  decode.one_of(decode.string |> decode.map(icu.Literal), [
    {
      use _ <- decode.field("hash", decode.bool)
      decode.success(icu.Hash)
    },
    {
      use name <- decode.field("name", decode.string)
      use kind <- decode.optional_field(
        "type",
        None,
        decode.optional(decode.string),
      )
      use cases <- decode.optional_field(
        "cases",
        dict.new(),
        decode.dict(decode.string, decode.list(decode.recursive(node_decoder))),
      )
      decode.success(icu.Argument(name, kind, cases))
    },
  ])
}

pub fn icu_parse_test() {
  let result = {
    decode.one_of(
      {
        use nodes <- decode.field("ok", decode.list(node_decoder()))
        decode.success(Parsed(nodes))
      },
      [
        {
          use message <- decode.field("error", decode.string)
          decode.success(Failed(message))
        },
      ],
    )
  }
  let entry = {
    use src <- decode.field("src", decode.string)
    use out <- decode.field("out", result)
    decode.success(#(src, out))
  }
  use #(src, expected) <- list.each(support.golden("icu_parse", entry))
  let got = case icu.parse(src) {
    Ok(nodes) -> Parsed(nodes)
    Error(message) -> Failed(message)
  }
  assert got == expected as why("icu_parse", src)
}

pub fn icu_format_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use src <- decode.field("src", decode.string)
    use args <- decode.field("args", support.args_decoder())
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, src, args, out))
  }
  use #(lang, src, args, out) <- list.each(support.golden("icu_format", entry))
  let assert Ok(nodes) = icu.parse(src)
  assert icu.format(nodes, args, lang, None) == out
    as why("icu_format", string.inspect(#(lang, src, args)))
}

pub fn t_over_the_whole_catalog_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use key <- decode.field("key", decode.string)
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, key, out))
  }
  use #(lang, key, out) <- list.each(support.golden("t_all", entry))
  assert i18n.t(support.locale(lang), key, []) == out
    as why("t_all", string.inspect(#(lang, key)))
}

pub fn t_with_arguments_test() {
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use key <- decode.field("key", decode.string)
    use args <- decode.field("args", support.args_decoder())
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, key, args, out))
  }
  use #(lang, key, args, out) <- list.each(support.golden("t", entry))
  assert i18n.t(support.locale(lang), key, args) == out
    as why("t", string.inspect(#(lang, key, args)))
}

pub fn t_falls_back_to_the_source_language_test() {
  let messages = decode.dict(decode.string, decode.string)
  let by_language =
    support.golden_one(
      "fallback_catalog",
      decode.dict(support.lang_decoder(), messages),
    )
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use key <- decode.field("key", decode.string)
    use args <- decode.field("args", support.args_decoder())
    use out <- decode.field("out", decode.string)
    decode.success(#(lang, key, args, out))
  }
  use #(lang, key, args, out) <- list.each(support.golden("fallback", entry))
  assert i18n.t(Locale(by_language, lang), key, args) == out
    as why("fallback", string.inspect(#(lang, key, args)))
}

pub fn every_catalog_message_parses_test() {
  let catalog = support.catalog()
  use #(lang, messages) <- list.each(dict.to_list(catalog))
  use #(key, message) <- list.each(dict.to_list(messages))
  assert icu.parse(message) |> result_ok
    as { language.tag(lang) <> " " <> key <> " does not parse" }
}

fn result_ok(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}
