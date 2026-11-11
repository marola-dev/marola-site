//// The ICU message subset the catalogs use: `{arg}`, `{n, plural, ...}` with
//// `#`, and `{x, select, ...}`. A port of ui.js `parse` and `format`.

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import marola/language.{type Language, En, PtBr}
import marola/numfmt

pub type Node {
  Literal(String)
  Hash
  Argument(name: String, kind: Option(String), cases: Dict(String, List(Node)))
}

/// A message argument: a number prints in the language's format, text as is.
pub type Arg {
  Num(Float)
  Text(String)
}

/// The cursor: characters not read yet, and how many were read. Positions in
/// errors count Unicode characters, as ui.js counts UTF-16 units, so they
/// agree for text in the Basic Multilingual Plane.
type Cursor {
  Cursor(source: String, rest: List(String), pos: Int)
}

type Parsed(a) =
  Result(#(a, Cursor), String)

pub fn parse(source: String) -> Result(List(Node), String) {
  let chars =
    string.to_utf_codepoints(source)
    |> list.map(fn(cp) { string.from_utf_codepoints([cp]) })
  use #(nodes, cursor) <- result.try(message(Cursor(source, chars, 0), False))
  case cursor.rest {
    [] -> Ok(nodes)
    _ -> Error("i18n: unbalanced } in " <> source)
  }
}

fn advance(cursor: Cursor) -> Cursor {
  case cursor.rest {
    [_, ..rest] -> Cursor(..cursor, rest: rest, pos: cursor.pos + 1)
    [] -> cursor
  }
}

fn fail(cursor: Cursor, expected: String) -> Result(a, String) {
  Error(
    "i18n: expected "
    <> expected
    <> " at "
    <> int.to_string(cursor.pos)
    <> " in "
    <> cursor.source,
  )
}

/// JavaScript's `\s`.
fn is_space(char: String) -> Bool {
  case char {
    " " | "\t" | "\n" | "\r" | "\u{0B}" | "\u{0C}" | "\u{A0}" | "\u{1680}" ->
      True
    "\u{2028}"
    | "\u{2029}"
    | "\u{202F}"
    | "\u{205F}"
    | "\u{3000}"
    | "\u{FEFF}" -> True
    _ ->
      case string.to_utf_codepoints(char) {
        [cp] -> {
          let code = string.utf_codepoint_to_int(cp)
          code >= 0x2000 && code <= 0x200A
        }
        _ -> False
      }
  }
}

fn skip_spaces(cursor: Cursor) -> Cursor {
  case cursor.rest {
    [c, ..] ->
      case is_space(c) {
        True -> skip_spaces(advance(cursor))
        False -> cursor
      }
    [] -> cursor
  }
}

fn take_name(cursor: Cursor, acc: List(String)) -> #(List(String), Cursor) {
  case cursor.rest {
    [c, ..] ->
      case is_space(c) || c == "," || c == "{" || c == "}" {
        True -> #(list.reverse(acc), cursor)
        False -> take_name(advance(cursor), [c, ..acc])
      }
    [] -> #(list.reverse(acc), cursor)
  }
}

fn word(cursor: Cursor) -> Parsed(String) {
  let #(chars, after) = take_name(skip_spaces(cursor), [])
  case chars {
    [] -> fail(cursor, "a name")
    _ -> Ok(#(string.join(chars, ""), skip_spaces(after)))
  }
}

fn expect(cursor: Cursor, char: String) -> Result(Cursor, String) {
  case cursor.rest {
    [c, ..] if c == char -> Ok(advance(cursor))
    _ -> fail(cursor, char)
  }
}

fn flush(out: List(Node), text: List(String)) -> List(Node) {
  case text {
    [] -> out
    _ -> [Literal(string.join(list.reverse(text), "")), ..out]
  }
}

fn message(cursor: Cursor, in_plural: Bool) -> Parsed(List(Node)) {
  message_loop(cursor, in_plural, [], [])
}

fn message_loop(
  cursor: Cursor,
  in_plural: Bool,
  out: List(Node),
  text: List(String),
) -> Parsed(List(Node)) {
  case cursor.rest {
    [] | ["}", ..] -> Ok(#(list.reverse(flush(out, text)), cursor))
    ["{", ..] -> {
      use #(node, after) <- result.try(argument(advance(cursor), in_plural))
      message_loop(after, in_plural, [node, ..flush(out, text)], [])
    }
    ["#", ..] if in_plural ->
      message_loop(advance(cursor), in_plural, [Hash, ..flush(out, text)], [])
    [c, ..] -> message_loop(advance(cursor), in_plural, out, [c, ..text])
  }
}

fn argument(cursor: Cursor, in_plural: Bool) -> Parsed(Node) {
  use #(name, cursor) <- result.try(word(cursor))
  case cursor.rest {
    [",", ..] -> {
      use #(kind, cursor) <- result.try(word(advance(cursor)))
      use cursor <- result.try(expect(cursor, ","))
      use #(cases, cursor) <- result.try(cases(
        skip_spaces(cursor),
        in_plural || kind == "plural",
        dict.new(),
      ))
      use cursor <- result.try(expect(cursor, "}"))
      Ok(#(Argument(name, Some(kind), cases), cursor))
    }
    _ -> {
      use cursor <- result.try(expect(cursor, "}"))
      Ok(#(Argument(name, None, dict.new()), cursor))
    }
  }
}

fn cases(
  cursor: Cursor,
  in_plural: Bool,
  acc: Dict(String, List(Node)),
) -> Parsed(Dict(String, List(Node))) {
  case cursor.rest {
    [] | ["}", ..] -> Ok(#(acc, cursor))
    _ -> {
      use #(key, cursor) <- result.try(word(cursor))
      use cursor <- result.try(expect(cursor, "{"))
      use #(nodes, cursor) <- result.try(message(cursor, in_plural))
      use cursor <- result.try(expect(cursor, "}"))
      cases(skip_spaces(cursor), in_plural, dict.insert(acc, key, nodes))
    }
  }
}

/// ui.js `format`: `n` is the plural number that `#` prints.
pub fn format(
  nodes: List(Node),
  args: List(#(String, Arg)),
  language: Language,
  n: Option(Arg),
) -> String {
  list.map(nodes, fn(node) {
    case node {
      Literal(text) -> text
      Hash -> number(n, language)
      Argument(name, None, _) ->
        case list.key_find(args, name) {
          Error(Nil) -> "{" <> name <> "}"
          Ok(Num(f)) -> numfmt.format(f, language)
          Ok(Text(s)) -> s
        }
      Argument(name, Some("plural"), cases) -> {
        let v = option.from_result(list.key_find(args, name))
        let chosen =
          first_case(cases, ["=" <> key(v), plural_category(language, v)])
        format(chosen, args, language, v)
      }
      Argument(name, Some(_), cases) -> {
        let v = option.from_result(list.key_find(args, name))
        format(first_case(cases, [key(v)]), args, language, n)
      }
    }
  })
  |> string.join("")
}

/// The first of `keys` the message has, else its `other` case.
fn first_case(
  cases: Dict(String, List(Node)),
  keys: List(String),
) -> List(Node) {
  let found = list.find_map(keys, fn(k) { dict.get(cases, k) })
  case found {
    Ok(nodes) -> nodes
    Error(Nil) -> result.unwrap(dict.get(cases, "other"), [])
  }
}

/// What `#` prints: Intl formats the number, and NaN for what is not one.
fn number(value: Option(Arg), language: Language) -> String {
  let parsed = case value {
    Some(Num(f)) -> Ok(f)
    Some(Text(s)) -> parse_number(s)
    None -> Error(Nil)
  }
  case parsed {
    Ok(f) -> numfmt.format(f, language)
    Error(Nil) -> "NaN"
  }
}

/// A case key for a value: JavaScript's `String(v)`.
fn key(value: Option(Arg)) -> String {
  case value {
    Some(Num(f)) ->
      case int.to_float(float.truncate(f)) == f {
        True -> int.to_string(float.truncate(f))
        False -> float.to_string(f)
      }
    Some(Text(s)) -> s
    None -> "undefined"
  }
}

fn parse_number(text: String) -> Result(Float, Nil) {
  case float.parse(text) {
    Ok(f) -> Ok(f)
    Error(Nil) -> int.parse(text) |> result.map(int.to_float)
  }
}

/// CLDR plural category for the catalogs' two languages; text that is not a
/// number selects "other", as Intl does with NaN.
fn plural_category(language: Language, value: Option(Arg)) -> String {
  let number = case value {
    Some(Num(f)) -> Ok(f)
    Some(Text(s)) -> parse_number(s)
    None -> Error(Nil)
  }
  case number {
    Error(Nil) -> "other"
    Ok(f) -> {
      let n = float.absolute_value(f)
      case language {
        En if n == 1.0 -> "one"
        En -> "other"
        PtBr if n <. 2.0 -> "one"
        PtBr -> pt_many_or_other(n)
      }
    }
  }
}

/// CLDR 42+: a whole multiple of a million takes "many".
fn pt_many_or_other(n: Float) -> String {
  let whole = float.truncate(n)
  case int.to_float(whole) == n && whole % 1_000_000 == 0 {
    True -> "many"
    False -> "other"
  }
}
