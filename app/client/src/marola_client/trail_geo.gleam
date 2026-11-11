//// The trail routes as GeoJSON for the map's line layer. One source, many
//// features: the id of a feature is the position of its route, so a click on
//// the map and a click in the panel name the same route.

import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import marola/difficulty
import marola/fmt
import marola/geo.{type Point}
import marola/i18n.{type Locale}
import marola/trails.{type Route, type Trails}
import marola_client/config
import marola_client/dom
import marola_client/icons

pub fn colour(route: Route) -> String {
  config.band_colour(difficulty.band(route.difficulty))
}

/// The tooltip over a route: its icon, name and length.
pub fn tip(route: Route, loc: Locale) -> dom.Dom {
  dom.el("span", [], [
    icons.icon("footprints"),
    dom.text(
      " "
      <> route.name
      <> " · "
      <> fmt.value(loc, Some(route.length_km), " km", 1),
    ),
  ])
}

fn coordinates(line: List(Point)) -> Json {
  json.array(line, fn(p) { json.array([p.lon, p.lat], json.float) })
}

fn feature(id: Int, route: Route, loc: Locale) -> Result(Json, Nil) {
  case trails.drawable_lines(route) {
    [] -> Error(Nil)
    lines ->
      Ok(
        json.object([
          #("type", json.string("Feature")),
          #(
            "properties",
            json.object([
              #("id", json.int(id)),
              #("color", json.string(colour(route))),
              // MapLibre keeps a property that is not a number or text as
              // text anyway; the map parses this one back into DOM nodes.
              #(
                "tip",
                json.string(json.to_string(dom.to_json(tip(route, loc)))),
              ),
            ]),
          ),
          #(
            "geometry",
            json.object([
              #("type", json.string("MultiLineString")),
              #("coordinates", json.array(lines, coordinates)),
            ]),
          ),
        ]),
      )
  }
}

/// A route with no drawable line is left out, but keeps its id.
pub fn collection(trails: Option(Trails), loc: Locale) -> String {
  let features = case trails {
    None -> []
    Some(found) ->
      trails.routes(found)
      |> list.index_map(fn(route, id) { feature(id, route, loc) })
      |> list.filter_map(fn(result) { result })
  }
  json.object([
    #("type", json.string("FeatureCollection")),
    #("features", json.preprocessed_array(features)),
  ])
  |> json.to_string
}
