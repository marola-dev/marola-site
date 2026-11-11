//// The closed sets of the schema: each wire value has a variant, and a value
//// the page has not seen is kept, not lost.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import marola/area
import marola/band
import marola/difficulty
import marola/i18n
import marola/icu
import marola/language.{En, PtBr}
import marola/level
import marola/lore
import marola/note
import marola/water
import marola/wind
import support

const schema = "../../site/board.schema.json"

fn strings_at(path: List(String)) -> List(String) {
  let decoder = decode.at(path, decode.list(decode.optional(decode.string)))
  let values = support.parse_json(support.read(schema), decoder)
  list.filter_map(values, fn(v) { option.to_result(v, Nil) })
}

pub fn the_16_note_codes_of_the_schema_are_all_known_test() {
  let codes =
    strings_at(["$defs", "note_codes", "items", "properties", "code", "enum"])
  assert list.length(codes) == 16
  use code <- list.each(codes)
  let parsed = note.parse_code(code)
  assert parsed != note.Unknown(code)
  assert note.code_to_string(parsed) == code
}

pub fn the_other_closed_sets_of_the_schema_are_all_known_test() {
  use value <- list.each(strings_at(["$defs", "likelihood", "enum"]))
  assert level.parse(value) != level.Unknown(value)
  assert level.to_string(level.parse(value)) == value
  use value <- list.each(
    strings_at(["properties", "lore", "properties", "kind", "enum"]),
  )
  assert lore.parse_kind(value) != lore.Unknown(value)
  let wind_path = [
    "$defs", "beach", "properties", "hours", "items", "properties", "wind_level",
    "enum",
  ]
  use value <- list.each(strings_at(wind_path))
  assert wind.parse(value) != wind.Unknown(value)
  assert wind.to_string(wind.parse(value)) == value
}

pub fn a_water_condition_outside_the_set_is_kept_test() {
  assert water.parse_condition("proper") == water.Proper
  assert water.parse_condition("improper") == water.Improper
  assert water.parse_condition("unknown") == water.Unclassified
  assert water.parse_condition("closed") == water.Unknown("closed")
}

pub fn a_value_the_page_has_not_seen_is_kept_test() {
  assert level.parse("Extreme") == level.Unknown("Extreme")
  assert level.parse("low") == level.Unknown("low")
  assert wind.parse("gale") == wind.Unknown("gale")
  assert lore.parse_kind("poem") == lore.Unknown("poem")
  assert note.parse_code("new_code") == note.Unknown("new_code")
  assert note.code_to_string(note.Unknown("new_code")) == "new_code"
  assert difficulty.parse(Some("alpine_hiking"))
    == difficulty.Unknown("alpine_hiking")
}

pub fn a_trail_difficulty_picks_the_colour_band_test() {
  assert difficulty.band(difficulty.parse(Some("hiking"))) == band.Good
  assert difficulty.band(difficulty.parse(Some("mountain_hiking"))) == band.Fair
  assert difficulty.band(difficulty.parse(Some("alpine_hiking")))
    == band.Unscored
  assert difficulty.band(difficulty.parse(None)) == band.Unscored
  assert difficulty.to_string(difficulty.Hiking) == Some("hiking")
  assert difficulty.to_string(difficulty.Unrated) == None
}

pub fn a_non_string_in_a_closed_set_is_a_decode_error_test() {
  assert json.parse("5", level.decoder()) |> is_error
  assert json.parse("null", wind.decoder()) |> is_error
  assert json.parse("\"Extreme\"", level.decoder())
    == Ok(level.Unknown("Extreme"))
}

fn is_error(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> False
    Error(_) -> True
  }
}

pub fn language_tags_test() {
  assert language.from_tag("pt-BR") == Ok(PtBr)
  assert language.from_tag("en") == Ok(En)
  assert language.from_tag("fr") == Error(Nil)
  assert language.from_tag("pt-br") == Error(Nil)
  assert list.map(language.all, language.tag) == ["pt-BR", "en"]
  assert language.matching(Some("pt"), language.all) == Some(PtBr)
  assert language.matching(Some("en-GB"), [PtBr]) == None
}

pub fn a_message_that_does_not_parse_gives_its_key_test() {
  let catalog = support.catalog_of([#("broken", "{a"), #("fine", "ok")])
  assert i18n.t(i18n.Locale(catalog, En), "broken", []) == "broken"
  assert i18n.t(i18n.Locale(catalog, En), "fine", []) == "ok"
  assert i18n.t(i18n.Locale(catalog, En), "fine", [#("x", icu.Num(1.0))])
    == "ok"
}

pub fn water_points_and_lore_pick_their_classes_test() {
  assert band.css_class(water.condition_band(water.Proper)) == "c70"
  assert band.css_class(water.condition_band(water.Improper)) == "c0"
  assert band.css_class(water.condition_band(water.Unclassified)) == "cna"
  assert band.css_class(water.condition_band(water.Unknown("x"))) == "cna"
  assert lore.label_key(lore.Creature) == "lore.creature"
  assert lore.label_key(lore.Secret) == "lore.fact"
  assert lore.label_key(lore.Unknown("poem")) == "lore.fact"
}

pub fn areas_decode_from_a_bare_list_and_from_the_site_file_test() {
  let expected = [area.Area("rio", "Rio de Janeiro", -22.9, -43.2)]
  let bare =
    "[{\"id\": \"rio\", \"name\": \"Rio de Janeiro\", \"lat\": -22.9, \"lon\": -43.2, \"radius_km\": 20}]"
  let wrapped = "{\"areas\": " <> bare <> "}"
  assert json.parse(bare, area.list_decoder()) == Ok(expected)
  assert json.parse(wrapped, area.list_decoder()) == Ok(expected)
  assert json.parse("{\"id\": \"rio\"}", area.list_decoder()) |> is_error
  let no_centre = "[{\"id\": \"rio\", \"name\": \"Rio\", \"lat\": -22.9}]"
  assert json.parse(no_centre, area.list_decoder()) |> is_error
}
