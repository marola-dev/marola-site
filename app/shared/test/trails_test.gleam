//// The trail files and the board's fallback, through the decoder.

import gleam/json
import gleam/list
import gleam/option.{None, Some}
import marola/difficulty
import marola/geo
import marola/trail
import marola/trails.{type Trails}
import support

fn file(area: String) -> Trails {
  support.parse_json(
    support.read("../client/static/data/trails/" <> area <> ".json"),
    trails.decoder(),
  )
}

pub fn rio_groups_routes_by_bairro_test() {
  let rio = file("rio")
  assert rio.area == "rio"
  assert rio.ibge_municipality == Some("3304557")
  assert rio.licence == Some("ODbL-1.0")
  assert list.length(rio.groups) == 17
  assert list.length(trails.routes(rio)) == 113
  assert list.all(rio.groups, fn(g) { g.bairro != None && g.routes != [] })
}

pub fn rio_keeps_the_sac_scale_it_knows_and_the_one_it_does_not_test() {
  let kinds =
    trails.routes(file("rio"))
    |> list.map(fn(r) { r.difficulty })
    |> list.unique
  assert list.contains(kinds, difficulty.Hiking)
  assert list.contains(kinds, difficulty.MountainHiking)
  assert list.contains(kinds, difficulty.Unrated)
  assert list.contains(kinds, difficulty.Unknown("demanding_mountain_hiking"))
}

pub fn every_route_of_the_files_has_a_drawable_line_and_a_way_test() {
  list.each(["rio", "floripa"], fn(area) {
    let all = trails.routes(file(area))
    assert all != []
    assert list.all(all, fn(r) { trails.drawable_lines(r) != [] })
    assert list.all(all, fn(r) { r.osm_ways != [] })
  })
}

pub fn first_point_is_lat_then_lon_test() {
  let assert Ok(route) = trails.route_at(file("rio"), 0)
  let assert [[geo.Point(lat:, lon:), ..], ..] = route.lines
  assert lat <. -20.0 && lat >. -25.0
  assert lon <. -40.0 && lon >. -45.0
}

pub fn salvador_has_no_routes_and_says_why_test() {
  let salvador = file("salvador")
  assert trails.is_empty(salvador)
  assert salvador.ibge_municipality == Some("2927408")
  assert option.is_some(salvador.note)
}

pub fn route_at_finds_by_position_and_not_past_the_end_test() {
  let rio = file("rio")
  assert trails.route_at(rio, 112) |> result_ok
  assert trails.route_at(rio, 113) == Error(Nil)
  assert trails.route_at(rio, -1) == Error(Nil)
}

fn result_ok(r: Result(a, Nil)) -> Bool {
  case r {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn a_newer_schema_is_refused_test() {
  let body =
    "{\"schema\":2,\"area\":\"x\",\"ibge_municipality\":\"1\",\"source\":\"s\",\"licence\":\"l\",\"osm_base\":\"b\",\"bairros\":[]}"
  assert result_ok_json(json.parse(body, trails.decoder())) == False
}

fn result_ok_json(r: Result(a, json.DecodeError)) -> Bool {
  case r {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn a_missing_trails_key_in_a_bairro_is_an_error_test() {
  let body =
    "{\"schema\":1,\"area\":\"x\",\"ibge_municipality\":\"1\",\"source\":\"s\",\"licence\":\"l\",\"osm_base\":\"b\",\"bairros\":[{\"bairro\":\"A\",\"osm_relation\":1}]}"
  assert result_ok_json(json.parse(body, trails.decoder())) == False
}

pub fn board_trails_become_one_group_without_a_bairro_test() {
  let line = [geo.Point(-27.0, -48.0), geo.Point(-27.1, -48.1)]
  let one =
    trail.Trail(
      name: "Trilha A",
      length_km: 1.5,
      difficulty: difficulty.Hiking,
      surface: Some("dirt"),
      geometry: line,
      near_beach: None,
      near_lake: None,
    )
  let lone = trail.Trail(..one, name: "Ponto", geometry: [geo.Point(0.0, 0.0)])
  let result = trails.from_board("floripa", [one, lone])
  assert result.ibge_municipality == None
  assert result.groups
    == [
      trails.Group(bairro: None, routes: [
        trails.Route("Trilha A", 1.5, difficulty.Hiking, Some("dirt"), [], [
          line,
        ]),
      ]),
    ]
}

pub fn board_without_drawable_trails_has_no_group_test() {
  assert trails.from_board("rio", []).groups == []
}

pub fn way_url_points_at_the_osm_page_test() {
  assert trails.way_url(334_779_662)
    == "https://www.openstreetmap.org/way/334779662"
}
