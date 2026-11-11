//// Note lines, day names and signed numbers, against the real catalogs and
//// the text `Intl` prints.

import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import marola/datefmt
import marola/fmt
import marola/hour.{Shown}
import marola/language.{En, PtBr}
import marola/note.{Note}
import marola/notes
import support

fn shown(notes: List(String), codes: List(note.Note)) -> hour.Shown {
  Shown(h: "10:00", score: 50, notes:, note_codes: codes, best: False)
}

pub fn short_date_matches_intl_in_both_languages_test() {
  assert datefmt.short("2026-01-07", PtBr) == "7 de jan."
  assert datefmt.short("2026-11-30", PtBr) == "30 de nov."
  assert datefmt.short("2026-05-07", PtBr) == "7 de mai."
  assert datefmt.short("2026-09-01", En) == "Sep 1"
  assert datefmt.short("2026-12-25", En) == "Dec 25"
}

pub fn short_date_keeps_what_is_not_a_day_test() {
  assert datefmt.short("soon", En) == "soon"
  assert datefmt.short("2026-13-01", En) == "2026-13-01"
  assert datefmt.short("2026-00-01", PtBr) == "2026-00-01"
  assert datefmt.short("", PtBr) == ""
}

pub fn signed_prints_a_sign_unless_the_number_is_zero_test() {
  let pt = support.locale(PtBr)
  assert fmt.signed(pt, 0.5, 1) == "+0,5"
  assert fmt.signed(pt, -0.3, 1) == "-0,3"
  assert fmt.signed(pt, 0.0, 1) == "0,0"
  assert fmt.signed(pt, -0.04, 1) == "0,0"
  assert fmt.signed(pt, 1.25, 1) == "+1,3"
  assert fmt.signed(support.locale(En), -1.25, 1) == "-1.3"
}

fn code(c: note.Code, args: List(#(String, note.Arg))) -> note.Note {
  Note(c, dict.from_list(args))
}

pub fn a_code_reads_in_the_page_language_with_rounded_numbers_test() {
  let choppy = code(note.Choppy, [#("wave_m", note.Number(1.26))])
  let line = fn(l) { notes.of(shown(["choppy (1.26m waves)"], [choppy]), l) }
  assert line(support.locale(PtBr)) == ["mar picado (ondas de 1,3 m)"]
  assert line(support.locale(En)) == ["choppy (1.3m waves)"]
}

pub fn a_board_without_codes_keeps_its_english_lines_test() {
  assert notes.of(shown(["dark"], []), support.locale(PtBr)) == ["dark"]
}

pub fn a_code_with_no_key_keeps_the_board_english_test() {
  let new = code(note.Unknown("kelp_bloom"), [])
  let pt = support.locale(PtBr)
  assert notes.of(shown(["kelp on the beach"], [new]), pt)
    == ["kelp on the beach"]
  // No English line at the same position: the code itself.
  assert notes.of(shown([], [new]), pt) == ["kelp_bloom"]
}

pub fn lines_pair_with_codes_by_position_test() {
  let codes = [code(note.Dark, []), code(note.NoWindData, [])]
  assert notes.of(shown(["a", "b"], codes), support.locale(En))
    == ["dark", "no wind data"]
}

pub fn unfit_water_prints_the_day_and_a_missing_count_test() {
  let unfit =
    code(note.WaterUnfit, [
      #("source", note.Text("IMA/SC")),
      #("sampled_on", note.Text("2026-11-03")),
      #("point", note.Text("P1")),
      #("location", note.Text("Canasvieiras")),
      #("enterococci_per_100ml", note.Other),
    ])
  let en = notes.text(unfit, None, support.locale(En))
  assert en
    == "water unfit for bathing: IMA/SC Nov 3, P1 (Canasvieiras), count n/a"
}

pub fn unfit_water_prints_a_count_when_there_is_one_test() {
  let unfit =
    code(note.WaterUnfit, [
      #("source", note.Text("IMA/SC")),
      #("sampled_on", note.Text("2026-11-03")),
      #("point", note.Text("P1")),
      #("location", note.Text("Canasvieiras")),
      #("enterococci_per_100ml", note.Number(1200.0)),
    ])
  let line = notes.text(unfit, None, support.locale(PtBr))
  assert string.contains(line, "1.200 enterococos")
}

pub fn mixed_water_lists_the_places_to_avoid_test() {
  let mixed =
    code(note.WaterMixed, [
      #("proper", note.Number(2.0)),
      #("total", note.Number(3.0)),
      #("avoid", note.Places(["P1", "P2"])),
    ])
  assert notes.text(mixed, Some("x"), support.locale(En))
    == "2/3 points PRÓPRIA; avoid P1; P2"
}

pub fn minus_days_crosses_months_years_and_leap_days_test() {
  assert datefmt.minus_days("2026-11-11", 1) == "2026-11-10"
  assert datefmt.minus_days("2026-11-01", 2) == "2026-10-30"
  assert datefmt.minus_days("2026-01-01", 1) == "2025-12-31"
  assert datefmt.minus_days("2024-03-01", 1) == "2024-02-29"
  assert datefmt.minus_days("2025-03-01", 1) == "2025-02-28"
  assert datefmt.minus_days("2000-03-01", 1) == "2000-02-29"
  assert datefmt.minus_days("1900-03-01", 1) == "1900-02-28"
  assert datefmt.minus_days("2026-11-11", 0) == "2026-11-11"
  assert datefmt.minus_days("2026-03-01", 365) == "2025-03-01"
}

pub fn minus_days_keeps_what_is_not_a_day_test() {
  assert datefmt.minus_days("soon", 1) == "soon"
  assert datefmt.minus_days("2026-13-01", 1) == "2026-13-01"
  assert datefmt.minus_days("", 2) == ""
}
