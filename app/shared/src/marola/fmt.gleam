//// How app.js writes a number with its unit: `num`, `fmt` and `wavesText`.

import gleam/float
import gleam/option.{type Option, None, Some}
import gleam/string
import marola/i18n.{type Locale}
import marola/numfmt

/// A number with exactly `digits` fraction digits, in the page's language.
pub fn num(loc: Locale, n: Float, digits: Int) -> String {
  numfmt.fixed(n, loc.language, digits, digits)
}

/// A value and its unit; a no-break space keeps "6 s" together when a tooltip
/// cell wraps. No value reads "n/a".
pub fn value(
  loc: Locale,
  n: Option(Float),
  unit: String,
  digits: Int,
) -> String {
  case n {
    None -> i18n.t(loc, "common.na", [])
    Some(n) -> num(loc, n, digits) <> first_space_to_nbsp(unit)
  }
}

/// app.js `.replace(' ', '\u00a0')` changes the first space only.
fn first_space_to_nbsp(unit: String) -> String {
  case string.split_once(unit, " ") {
    Ok(#(before, after)) -> before <> "\u{A0}" <> after
    Error(Nil) -> unit
  }
}

/// The waves cell: height, and the period when there is one.
pub fn waves(
  loc: Locale,
  wave_m: Option(Float),
  period_s: Option(Float),
) -> String {
  i18n.t(loc, "cell.waves", [
    i18n.arg("m", value(loc, wave_m, " m", 1)),
    i18n.arg("every", case period_s {
      None -> "no"
      Some(_) -> "yes"
    }),
    i18n.arg("s", value(loc, period_s, " s", 0)),
  ])
}

/// A number with a sign unless it prints as zero: `Intl.NumberFormat` with
/// `signDisplay: 'exceptZero'`. The tide's height above the mean level.
pub fn signed(loc: Locale, n: Float, digits: Int) -> String {
  let body = num(loc, float.absolute_value(n), digits)
  let is_zero = body == num(loc, 0.0, digits)
  case is_zero, n <. 0.0 {
    True, _ -> body
    False, True -> "-" <> body
    False, False -> "+" <> body
  }
}
