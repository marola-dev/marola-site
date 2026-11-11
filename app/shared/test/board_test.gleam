//// The board decoder against the fixtures and against boards that are wrong.

import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import marola/board.{type Board}
import marola/difficulty
import marola/level
import marola/lore
import marola/note
import marola/trail
import marola/water
import marola/wind
import support

const fixture = "../../site/fixtures/board.json"

const fixture_v1 = "../../site/fixtures/board-schema1.json"

fn decode(text: String) -> Result(Board, json.DecodeError) {
  json.parse(text, board.decoder())
}

fn decoded(text: String) -> Board {
  case decode(text) {
    Ok(b) -> b
    Error(error) ->
      panic as { "board does not decode: " <> string.inspect(error) }
  }
}

fn is_error(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> False
    Error(_) -> True
  }
}

pub fn the_schema_2_fixture_decodes_test() {
  let b = decoded(support.read(fixture))
  assert b.schema == 2
  assert b.area == "fixture"
  assert b.lore == None
  assert b.sources.water == Some("IMA/SC")
  assert list.map(b.beaches, fn(x) { x.name })
    == ["Praia da Joaquina", "Praia Brava"]
  assert b.trails == []
  assert board.hours(b) == ["07:00", "09:00", "10:00", "12:00", "13:00"]
  let assert [joaquina, brava] = b.beaches
  assert joaquina.best.score == 55
  assert list.length(joaquina.best.note_codes) == 2
  let assert [first, ..] = joaquina.best.note_codes
  assert first.code == note.Breezy
  assert dict.get(first.args, "wind_kmh") == Ok(note.Number(27.0))
  assert brava.water.unfit
  let assert [point] = brava.water.points
  assert point.condition == water.Improper
  assert point.enterococci_per_100ml == Some(800)
  let assert [_, twelve] = brava.hours
  assert twelve.sea_temp_c == None
  assert twelve.wind_level == None
}

pub fn the_schema_1_fixture_has_no_note_codes_test() {
  let b = decoded(support.read(fixture_v1))
  assert b.schema == 1
  assert list.all(b.beaches, fn(x) { x.best.note_codes == [] })
}

pub fn schema_3_is_rejected_test() {
  let text =
    string.replace(support.read(fixture), "\"schema\": 2", "\"schema\": 3")
  let assert Error(json.UnableToDecode(errors)) = decode(text)
  assert string.inspect(errors) |> string.contains("schema 1 or 2")
}

pub fn a_board_that_is_wrong_is_an_error_not_a_crash_test() {
  let text = support.read(fixture)
  assert is_error(decode("{"))
  assert is_error(decode("[]"))
  assert is_error(decode(string.replace(text, "\"area\": \"fixture\",", "")))
  assert is_error(
    decode(string.replace(text, "\"score\": 48", "\"score\": \"48\"")),
  )
  assert is_error(
    decode(string.replace(text, "\"lat\": -27.6296", "\"lat\": null")),
  )
}

pub fn trails_are_optional_and_decode_when_present_test() {
  let trail =
    "{\"name\": \"Trilha da Lagoinha\", \"length_km\": 2, \"difficulty\": \"mountain_hiking\", \"surface\": null, \"geometry\": [[-27.5, -48.4], [-27.51, -48.41]], \"near_beach\": {\"name\": \"Brava\", \"distance_km\": 0.3}, \"near_lake\": null}"
  let one_point =
    "{\"name\": \"Curta\", \"length_km\": 0.1, \"difficulty\": null, \"surface\": \"dirt\", \"geometry\": [[-27.5, -48.4]], \"near_beach\": null, \"near_lake\": null}"
  let text =
    string.replace(
      support.read(fixture),
      "\"beaches\": [",
      "\"trails\": [" <> trail <> "," <> one_point <> "], \"beaches\": [",
    )
  let b = decoded(text)
  let assert [long, short] = b.trails
  assert long.difficulty == difficulty.MountainHiking
  assert long.length_km == 2.0
  assert long.near_beach == Some(trail.NearAnchor("Brava", 0.3))
  assert long.near_lake == None
  assert list.length(long.geometry) == 2
  assert short.difficulty == difficulty.Unrated
  assert list.filter(b.trails, trail.drawable) == [long]
  assert short.surface == Some("dirt")
}

pub fn a_value_outside_a_closed_set_becomes_unknown_test() {
  let text =
    support.read(fixture)
    |> string.replace("\"Low\"", "\"Extreme\"")
    |> string.replace("\"calm\"", "\"gale\"")
    |> string.replace("\"proper\"", "\"mystery\"")
    |> string.replace(
      "\"lore\": null",
      "\"lore\": {\"kind\": \"poem\", \"text\": \"t\", \"source\": \"javascript:alert(1)\", \"lang\": \"en\"}",
    )
    |> string.replace("\"breezy\", \"args\"", "\"new_code\", \"args\"")
  let b = decoded(text)
  let assert [joaquina, ..] = b.beaches
  assert joaquina.jellyfish == level.Unknown("Extreme")
  let assert [first, ..] = joaquina.hours
  assert first.jellyfish == level.Unknown("Extreme")
  assert first.wind_level == Some(wind.Unknown("gale"))
  let assert [point, ..] = joaquina.water.points
  assert point.condition == water.Unknown("mystery")
  assert b.lore
    == Some(lore.Lore(lore.Unknown("poem"), "t", "javascript:alert(1)", "en"))
  let assert [code, ..] = joaquina.best.note_codes
  assert code.code == note.Unknown("new_code")
}

pub fn note_args_of_every_shape_decode_test() {
  let text =
    string.replace(
      support.read(fixture),
      "\"args\": {\"wind_kmh\": 27}",
      "\"args\": {\"wind_kmh\": 27, \"place\": \"x\", \"avoid\": [\"a\", \"b\"], \"odd\": null, \"nested\": {\"a\": 1}}",
    )
  let b = decoded(text)
  let assert [joaquina, ..] = b.beaches
  let assert [first, ..] = joaquina.best.note_codes
  assert dict.get(first.args, "place") == Ok(note.Text("x"))
  assert dict.get(first.args, "avoid") == Ok(note.Places(["a", "b"]))
  assert dict.get(first.args, "odd") == Ok(note.Other)
  assert dict.get(first.args, "nested") == Ok(note.Other)
}
