//// The view helpers and the JSON the map reads: what a visitor sees and what
//// `maplibre_ffi.mjs` is told.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import marola/beach.{Beach}
import marola/board.{Board}
import marola/geo
import marola/trails
import marola_client/cmd
import marola_client/effects
import marola_client/map_view
import marola_client/model as mdl
import marola_client/msg
import marola_client/trail_geo
import marola_client/update
import marola_client/view
import marola_client/view/bar
import marola_client/view/card
import marola_client/view/footer
import marola_client/view/list as beach_list
import marola_client/view/trails_view
import support

fn page(search: String) -> mdl.Model {
  support.loaded(search).0
}

fn html_of(model: mdl.Model) -> String {
  element.to_string(view.view(model))
}

fn count(text: String, part: String) -> Int {
  list.length(string.split(text, part)) - 1
}

pub fn coordinates_keep_the_dot_in_every_language_test() {
  assert card.fixed4(-27.6296) == "-27.6296"
  assert card.fixed4(-27.5) == "-27.5000"
  assert card.fixed4(0.00004) == "0.0000"
  assert card.fixed4(-0.00004) == "0.0000"
}

pub fn the_list_ranks_by_score_and_then_by_distance_test() {
  let model = page("")
  let by_score = beach_list.ranked(model)
  assert list.length(by_score) == 2
  assert list.all(by_score, fn(entry) { entry.1 == None })
  let near_brava = geo.Point(-27.43, -48.4)
  let #(nearby, _) = update.update(model, msg.Located(Ok(near_brava)))
  let by_distance = beach_list.ranked(nearby)
  let assert [#(first, Some(a)), #(_, Some(b))] = by_distance
  assert a <=. b
  assert first.name == "Praia Brava"
}

pub fn the_hour_slider_reads_the_selection_test() {
  let model = page("")
  assert bar.hour_index(model) == -1
  let #(moved, _) = update.update(model, msg.HourMoved(1))
  assert bar.hour_index(moved) == 1
}

pub fn the_footer_names_the_board_once_it_is_on_show_test() {
  let model = page("")
  let text = element.to_string(element.fragment(footer.status_line(model)))
  assert string.contains(text, "Open-Meteo")
  assert string.contains(text, "2 praias")
  assert string.contains(text, "https://open-meteo.com/")
}

pub fn the_footer_says_what_failed_test() {
  let model = mdl.Model(..page(""), status: mdl.Failed("404 data/x.json", True))
  let text = element.to_string(element.fragment(footer.status_line(model)))
  assert string.contains(text, "404 data/x.json")
}

pub fn the_page_has_one_dot_per_beach_in_the_map_json_test() {
  let model = page("")
  let text = map_view.sync_json(model)
  assert count(text, "\"click\":\"beach\"") == 2
}

pub fn the_water_layer_adds_every_sampling_point_test() {
  let quiet = map_view.sync_json(page(""))
  let #(on, _) = update.update(page(""), msg.LayerPressed(mdl.Water))
  let water = map_view.sync_json(on)
  assert count(water, "\"tip_class\":\"\"") > count(quiet, "\"tip_class\":\"\"")
}

pub fn a_beach_name_with_markup_stays_text_test() {
  let hostile = "<img src=x onerror=alert(1)>"
  let model = page("")
  let assert Some(b) = model.board
  let assert [first, ..rest] = b.beaches
  let renamed = Board(..b, beaches: [Beach(..first, name: hostile), ..rest])
  let text =
    html_of(mdl.Model(..model, board: Some(renamed), selected: Some(hostile)))
  assert !string.contains(text, "<img src=x")
  assert string.contains(text, "&lt;img src=x")
}

pub fn the_card_opens_for_the_picked_beach_and_nothing_else_test() {
  let closed = html_of(page(""))
  assert count(closed, "class=\"card\" hidden") == 1
  let #(open, _) =
    update.update(page(""), msg.BeachPicked("Praia Brava", False))
  let text = html_of(open)
  assert string.contains(text, "<h2>Praia Brava</h2>")
  assert count(text, "class=\"close\"") == 1
}

pub fn the_layer_buttons_mark_the_one_on_show_test() {
  let #(on, _) = update.update(page(""), msg.LayerPressed(mdl.Water))
  let text = html_of(on)
  assert string.contains(text, "data-layer=\"water\"")
  assert count(text, "data-layer=") == 7
  assert count(text, "disabled") >= 7
  assert string.contains(text, "layer-water")
}

pub fn the_day_buttons_name_today_and_tomorrow_test() {
  let text = html_of(page(""))
  assert count(text, "data-day=") == 1
  assert string.contains(text, "hoje")
}

pub fn a_failed_map_hides_the_rail_and_says_why_test() {
  let #(failed, _) = update.update(page(""), msg.MapEvent("error", "style"))
  let text = html_of(failed)
  assert string.contains(text, "o mapa não abriu neste navegador")
  assert !string.contains(text, "id=\"flow\"")
  assert failed.panel == mdl.BeachList
}

pub fn the_map_json_is_valid_json_with_one_part_per_layer_test() {
  let text = map_view.sync_json(page(""))
  assert string.contains(text, "\"markers\"")
  assert string.contains(text, "\"trails\":{\"visible\":true,\"selected\":-1}")
  assert json_ok(text)
}

fn json_ok(text: String) -> Bool {
  case json.parse(text, decode.dynamic) {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn rio_has_113_routes_on_the_map_and_each_has_a_line_test() {
  let found = support.trails_file("rio")
  let text = trail_geo.collection(Some(found), page("").loc)
  assert count(text, "\"type\":\"Feature\"") == 113
  assert count(text, "\"color\":\"#") == 113
}

pub fn salvador_has_no_routes_and_a_note_test() {
  let found = support.trails_file("salvador")
  assert trails.is_empty(found)
  assert found.note != None
  let model =
    mdl.Model(
      ..page(""),
      trails_file: mdl.TrailsLoaded(found),
      panel: mdl.TrailList,
    )
  let text = html_of(model)
  let assert Some(note) = found.note
  assert string.contains(text, string.slice(note, 0, 20))
  assert !string.contains(text, "data-trail=")
}

pub fn the_trail_panel_groups_routes_by_bairro_with_the_municipality_test() {
  let found = support.trails_file("rio")
  let model =
    mdl.Model(
      ..page(""),
      trails_file: mdl.TrailsLoaded(found),
      panel: mdl.TrailList,
    )
  let text = html_of(model)
  assert count(text, "data-trail=") == 113
  assert count(text, "class=\"trail-group\"") == 17
  assert string.contains(text, "3304557")
}

pub fn a_picked_route_links_its_osm_ways_test() {
  let found = support.trails_file("floripa")
  let model = mdl.Model(..page(""), trails_file: mdl.TrailsLoaded(found))
  let #(picked, _) = update.update(model, msg.TrailChosen(0, True))
  let assert Some(route) = trails_view.picked(picked)
  let text = element.to_string(trails_view.card(picked, route))
  let assert [way, ..] = route.osm_ways
  assert string.contains(
    text,
    "https://www.openstreetmap.org/way/" <> int.to_string(way),
  )
  assert string.contains(text, "rel=\"noopener\"")
}

pub fn without_a_trail_file_the_board_trails_stand_in_test() {
  let model = mdl.Model(..page(""), trails_file: mdl.TrailsMissing)
  assert mdl.trails(model) != None
  let pending = mdl.Model(..page(""), trails_file: mdl.TrailsPending)
  assert mdl.trails(pending) == None
}

pub fn camera_commands_become_the_json_the_ffi_reads_test() {
  assert effects.camera_json(cmd.Pan(1.5, -2.5))
    == "{\"kind\":\"pan\",\"lon\":1.5,\"lat\":-2.5}"
  assert string.contains(
    effects.camera_json(cmd.Fit(1.0, 2.0, 3.0, 4.0, 40, 13, True)),
    "\"max_zoom\":13",
  )
  assert effects.camera_json(cmd.MinZoom(0))
    == "{\"kind\":\"minzoom\",\"zoom\":0}"
}

pub fn the_map_config_carries_the_style_and_the_credit_test() {
  let text = effects.map_config(-48.5, -27.6)
  assert string.contains(text, "tiles.openfreemap.org/styles/liberty")
  assert string.contains(text, "OpenStreetMap contributors")
  assert string.contains(text, "/vendor/maplibre/maplibre-gl-worker.mjs")
}
