//// The reason lines of a score, in the page's language. A port of app.js
//// `noteText` and `notesOf`: a code with a catalog key reads in the language;
//// a code this page has no key for keeps the board's English.

import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import marola/datefmt
import marola/fmt
import marola/hour.{type Shown}
import marola/i18n.{type Locale}
import marola/icu
import marola/note.{type Arg, type Note}

/// The lines for a shown hour. A board with no note codes (schema 1) has only
/// the English lines.
pub fn of(shown: Shown, loc: Locale) -> List(String) {
  case shown.note_codes {
    [] -> shown.notes
    codes ->
      list.index_map(codes, fn(code, i) {
        text(
          code,
          list.drop(shown.notes, i) |> list.first |> option.from_result,
          loc,
        )
      })
  }
}

pub fn text(note: Note, english: Option(String), loc: Locale) -> String {
  let args =
    dict.to_list(note.args)
    |> list.map(fn(entry) { to_arg(loc, entry.0, entry.1) })
  let args = case list.key_find(args, "enterococci_per_100ml") {
    Ok(_) -> args
    Error(Nil) -> [i18n.arg("enterococci_per_100ml", "na"), ..args]
  }
  let key = "note." <> note.code_to_string(note.code)
  let out = i18n.t(loc, key, args)
  case out == key {
    False -> out
    True ->
      case english {
        Some(line) -> line
        None -> note.code_to_string(note.code)
      }
  }
}

/// The numbers the English lines rounded; a day and a list of places as the
/// page prints them.
fn to_arg(loc: Locale, name: String, arg: Arg) -> #(String, icu.Arg) {
  case name, arg {
    "wave_m", note.Number(v) | "sea_temp_c", note.Number(v) ->
      i18n.arg(name, fmt.num(loc, v, 1))
    "wind_kmh", note.Number(v) | "rain_pct", note.Number(v) ->
      i18n.arg(name, fmt.num(loc, v, 0))
    "sampled_on", note.Text(day) ->
      i18n.arg(name, datefmt.short(day, loc.language))
    "avoid", note.Places(places) -> i18n.arg(name, string.join(places, "; "))
    _, note.Number(v) -> i18n.number_arg(name, v)
    _, note.Text(s) -> i18n.arg(name, s)
    _, note.Places(places) -> i18n.arg(name, string.join(places, ","))
    // A null: the only one the catalog reads is the bacteria count.
    "enterococci_per_100ml", note.Other -> i18n.arg(name, "na")
    _, note.Other -> i18n.arg(name, "null")
  }
}
