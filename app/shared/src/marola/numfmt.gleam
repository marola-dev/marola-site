//// Number formatting for pt-BR and en, without Intl, so Erlang and JavaScript
//// print the same text. It rounds the shortest decimal text of the float, half
//// away from zero, as ECMA-402 does, so 1.005 prints 1.01.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import marola/language.{type Language, En, PtBr}

/// What `new Intl.NumberFormat(locale).format(n)` prints: up to 3 fraction digits.
pub fn format(n: Float, language: Language) -> String {
  fixed(n, language, 0, 3)
}

/// Like Intl's minimumFractionDigits and maximumFractionDigits.
pub fn fixed(n: Float, language: Language, min: Int, max: Int) -> String {
  let #(digits, point) = decimal(float.absolute_value(n))
  let #(digits, point) = round(digits, point, max)
  let whole = whole_part(digits, point)
  let fraction = fraction_part(digits, point, min)
  let #(group, decimal_mark) = separators(language)
  let body = case fraction {
    "" -> grouped(whole, group)
    _ -> grouped(whole, group) <> decimal_mark <> fraction
  }
  case n <. 0.0 {
    True -> "-" <> body
    False -> body
  }
}

fn separators(language: Language) -> #(String, String) {
  case language {
    PtBr -> #(".", ",")
    En -> #(",", ".")
  }
}

/// The significant digits and the count of digits before the decimal point
/// (zero or negative for 0.00ddd): the value is 0.DIGITS * 10^point.
fn decimal(n: Float) -> #(List(String), Int) {
  let text = float.to_string(n)
  let #(mantissa, exponent) = case string.split(text, "e") {
    [m, e] -> #(m, int.parse(e) |> result_or(0))
    _ -> #(text, 0)
  }
  let #(whole, fraction) = case string.split(mantissa, ".") {
    [w, f] -> #(w, f)
    _ -> #(mantissa, "")
  }
  let all = string.to_graphemes(whole <> fraction)
  let point = string.length(whole) + exponent
  strip_leading_zeros(all, point)
}

fn result_or(result: Result(Int, Nil), default: Int) -> Int {
  case result {
    Ok(value) -> value
    Error(Nil) -> default
  }
}

fn strip_leading_zeros(
  digits: List(String),
  point: Int,
) -> #(List(String), Int) {
  case digits {
    ["0", ..rest] -> strip_leading_zeros(rest, point - 1)
    _ ->
      case list.all(digits, fn(d) { d == "0" }) {
        True -> #([], 0)
        False -> #(digits, point)
      }
  }
}

/// Keep `point + max` digits; a dropped digit of 5 or more rounds up.
fn round(digits: List(String), point: Int, max: Int) -> #(List(String), Int) {
  let keep = point + max
  case keep < 0 || keep >= list.length(digits) {
    True ->
      case keep < 0 {
        True -> #([], 0)
        False -> #(digits, point)
      }
    False -> {
      let kept = list.take(digits, keep)
      let next = list.drop(digits, keep) |> list.first |> result_digit
      case next >= 5 {
        False -> #(kept, point)
        True -> increment(kept, point)
      }
    }
  }
}

fn result_digit(digit: Result(String, Nil)) -> Int {
  case digit {
    Ok(d) -> int.parse(d) |> result_or(0)
    Error(Nil) -> 0
  }
}

/// Add one unit in the last kept place; a carry out of the first digit adds a digit.
fn increment(kept: List(String), point: Int) -> #(List(String), Int) {
  let carried =
    list.fold_right(kept, #([], True), fn(acc, digit) {
      let #(done, carry) = acc
      case carry, int.parse(digit) |> result_or(0) {
        True, 9 -> #(["0", ..done], True)
        True, d -> #([int.to_string(d + 1), ..done], False)
        False, _ -> #([digit, ..done], False)
      }
    })
  case carried {
    #(done, True) -> #(["1", ..done], point + 1)
    #(done, False) -> #(done, point)
  }
}

fn whole_part(digits: List(String), point: Int) -> String {
  case point <= 0 {
    True -> "0"
    False -> {
      let padded = list.append(digits, list.repeat("0", point))
      list.take(padded, point) |> string.join("")
    }
  }
}

fn fraction_part(digits: List(String), point: Int, min: Int) -> String {
  let leading = case point < 0 {
    True -> list.repeat("0", -point)
    False -> []
  }
  let after_point = case point < 0 {
    True -> digits
    False -> list.drop(digits, point)
  }
  let all = list.append(leading, after_point)
  let trimmed = trim_trailing_zeros(all, min)
  let padded =
    list.append(trimmed, list.repeat("0", min - list.length(trimmed)))
  string.join(padded, "")
}

fn trim_trailing_zeros(digits: List(String), min: Int) -> List(String) {
  case list.length(digits) > min, list.reverse(digits) {
    True, ["0", ..rest] -> trim_trailing_zeros(list.reverse(rest), min)
    _, _ -> digits
  }
}

fn grouped(whole: String, separator: String) -> String {
  let digits = string.to_graphemes(whole)
  let first = case list.length(digits) % 3 {
    0 -> 3
    n -> n
  }
  group_loop(digits, first, separator, [])
  |> list.reverse
  |> string.join("")
}

fn group_loop(
  digits: List(String),
  take: Int,
  separator: String,
  acc: List(String),
) -> List(String) {
  case digits {
    [] -> acc
    _ -> {
      let chunk = string.join(list.take(digits, take), "")
      let acc = case acc {
        [] -> [chunk]
        _ -> [chunk, separator, ..acc]
      }
      group_loop(list.drop(digits, take), 3, separator, acc)
    }
  }
}
