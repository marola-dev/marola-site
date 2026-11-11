//// Hiking routes of an area (OpenStreetMap, ODbL 1.0), grouped by bairro. The
//// static file `data/trails/<area>.json` carries them; a board's own optional
//// `trails` array (MIP-0030) is the fallback when an area has no file.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import marola/decoders
import marola/difficulty.{type Difficulty}
import marola/geo.{type Point}
import marola/trail.{type Trail}

/// The file schema this page reads.
pub const schema = 1

/// One named route: the lines are the OSM ways that make it, each a list of
/// points, so a route with gaps stays in pieces.
pub type Route {
  Route(
    name: String,
    length_km: Float,
    difficulty: Difficulty,
    surface: Option(String),
    osm_ways: List(Int),
    lines: List(List(Point)),
  )
}

/// The routes of one bairro. A board's trails belong to no bairro.
pub type Group {
  Group(bairro: Option(String), routes: List(Route))
}

pub type Trails {
  Trails(
    area: String,
    ibge_municipality: Option(String),
    source: String,
    licence: Option(String),
    osm_base: Option(String),
    note: Option(String),
    groups: List(Group),
  )
}

/// Every route, in the order the panel lists them. The position is the
/// route's id on the map and in the panel.
pub fn routes(trails: Trails) -> List(Route) {
  list.flat_map(trails.groups, fn(group) { group.routes })
}

pub fn route_at(trails: Trails, id: Int) -> Result(Route, Nil) {
  // `list.drop` with a negative count keeps the whole list.
  case id < 0 {
    True -> Error(Nil)
    False -> routes(trails) |> list.drop(id) |> list.first
  }
}

pub fn is_empty(trails: Trails) -> Bool {
  routes(trails) == []
}

/// A line with fewer than two points cannot be drawn.
pub fn drawable_lines(route: Route) -> List(List(Point)) {
  list.filter(route.lines, fn(line) {
    case line {
      [_, _, ..] -> True
      _ -> False
    }
  })
}

/// The OSM page of a way. The id is a number, so the link needs no checking.
pub fn way_url(id: Int) -> String {
  "https://www.openstreetmap.org/way/" <> int.to_string(id)
}

/// The board's trails as one group with no bairro. Its source is the board
/// generator's, which reads OSM.
pub fn from_board(area: String, trails: List(Trail)) -> Trails {
  let routes =
    list.filter(trails, trail.drawable)
    |> list.map(fn(t) {
      Route(
        name: t.name,
        length_km: t.length_km,
        difficulty: t.difficulty,
        surface: t.surface,
        osm_ways: [],
        lines: [t.geometry],
      )
    })
  Trails(
    area:,
    ibge_municipality: None,
    source: "OpenStreetMap contributors",
    licence: Some("ODbL-1.0"),
    osm_base: None,
    note: None,
    groups: case routes {
      [] -> []
      _ -> [Group(bairro: None, routes:)]
    },
  )
}

/// A `[lat, lon]` pair.
fn point_decoder() -> Decoder(Point) {
  decode.list(decoders.number())
  |> decode.then(fn(pair) {
    case pair {
      [lat, lon] -> decode.success(geo.Point(lat:, lon:))
      _ -> decode.failure(geo.Point(0.0, 0.0), "a [lat, lon] pair")
    }
  })
}

fn route_decoder() -> Decoder(Route) {
  use name <- decode.field("name", decode.string)
  use length_km <- decode.field("length_km", decoders.number())
  use difficulty <- decode.field("difficulty", difficulty.decoder())
  use surface <- decode.field("surface", decode.optional(decode.string))
  use osm_ways <- decode.field("osm_ways", decode.list(decode.int))
  use lines <- decode.field("lines", decode.list(decode.list(point_decoder())))
  decode.success(Route(
    name:,
    length_km:,
    difficulty:,
    surface:,
    osm_ways:,
    lines:,
  ))
}

fn group_decoder() -> Decoder(Group) {
  use bairro <- decode.field("bairro", decode.string)
  use routes <- decode.field("trails", decode.list(route_decoder()))
  decode.success(Group(bairro: Some(bairro), routes:))
}

pub fn decoder() -> Decoder(Trails) {
  use found <- decode.field("schema", decode.int)
  case found == schema {
    False ->
      decode.failure(
        Trails("", None, "", None, None, None, []),
        "schema " <> int.to_string(schema),
      )
    True -> body()
  }
}

fn body() -> Decoder(Trails) {
  use area <- decode.field("area", decode.string)
  use ibge_municipality <- decode.field("ibge_municipality", decode.string)
  use source <- decode.field("source", decode.string)
  use licence <- decode.field("licence", decode.string)
  use osm_base <- decode.field("osm_base", decode.string)
  use note <- decode.optional_field(
    "note",
    None,
    decode.optional(decode.string),
  )
  use groups <- decode.field("bairros", decode.list(group_decoder()))
  decode.success(Trails(
    area:,
    ibge_municipality: Some(ibge_municipality),
    source:,
    licence: Some(licence),
    osm_base: Some(osm_base),
    note:,
    groups:,
  ))
}
