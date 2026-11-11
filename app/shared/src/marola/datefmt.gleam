//// A calendar day as the page prints it: `Intl.DateTimeFormat(locale, {day:
//// 'numeric', month: 'short'})` on a UTC date. Written out as tables so
//// Erlang and JavaScript print the same text.

import gleam/int
import gleam/list
import gleam/string
import marola/language.{type Language, En, PtBr}

const pt_months = [
  "jan.", "fev.", "mar.", "abr.", "mai.", "jun.", "jul.", "ago.", "set.", "out.",
  "nov.", "dez.",
]

const en_months = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
  "Dec",
]

/// "2026-11-07" is "7 de nov." in pt-BR and "Nov 7" in English. Text that is
/// not an ISO day comes back as it is.
pub fn short(iso: String, language: Language) -> String {
  let parsed = case string.split(iso, "-") {
    [_, month, day] -> #(int.parse(month), int.parse(string.slice(day, 0, 2)))
    _ -> #(Error(Nil), Error(Nil))
  }
  case parsed {
    #(Ok(month), Ok(day)) if month >= 1 && month <= 12 -> {
      let names = case language {
        PtBr -> pt_months
        En -> en_months
      }
      case list.drop(names, month - 1) {
        [name, ..] ->
          case language {
            PtBr -> int.to_string(day) <> " de " <> name
            En -> name <> " " <> int.to_string(day)
          }
        [] -> iso
      }
    }
    _ -> iso
  }
}

/// The ISO day `days` before `iso`, by the proleptic Gregorian calendar. A
/// text that is not an ISO day comes back as it is. The satellite layers ask
/// for the imagery of a day or two before the board's.
pub fn minus_days(iso: String, days: Int) -> String {
  case string.split(iso, "-") {
    [y, m, d] ->
      case int.parse(y), int.parse(m), int.parse(d) {
        Ok(year), Ok(month), Ok(day)
          if year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= 31
        -> from_days(to_days(year, month, day) - days)
        _, _, _ -> iso
      }
    _ -> iso
  }
}

/// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
fn to_days(year: Int, month: Int, day: Int) -> Int {
  let y = case month <= 2 {
    True -> year - 1
    False -> year
  }
  let era = y / 400
  let yoe = y - era * 400
  let shifted = case month > 2 {
    True -> month - 3
    False -> month + 9
  }
  let doy = { 153 * shifted + 2 } / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146_097 + doe - 719_468
}

fn from_days(days: Int) -> String {
  let z = days + 719_468
  let era = z / 146_097
  let doe = z - era * 146_097
  let yoe = { doe - doe / 1460 + doe / 36_524 - doe / 146_096 } / 365
  let doy = doe - { 365 * yoe + yoe / 4 - yoe / 100 }
  let mp = { 5 * doy + 2 } / 153
  let day = doy - { 153 * mp + 2 } / 5 + 1
  let month = case mp < 10 {
    True -> mp + 3
    False -> mp - 9
  }
  let year = case month <= 2 {
    True -> yoe + era * 400 + 1
    False -> yoe + era * 400
  }
  pad(year, 4) <> "-" <> pad(month, 2) <> "-" <> pad(day, 2)
}

fn pad(n: Int, width: Int) -> String {
  string.pad_start(int.to_string(n), width, "0")
}
