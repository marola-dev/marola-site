//// An OSM trail within 500 m of a beach or a named lake (MIP-0030).

import gleam/dynamic/decode.{type Decoder}
import gleam/option.{type Option}
import marola/decoders
import marola/difficulty.{type Difficulty}
import marola/geo.{type Point}

/// The nearer beach or lake of a kind.
pub type NearAnchor {
  NearAnchor(name: String, distance_km: Float)
}

pub type Trail {
  Trail(
    name: String,
    length_km: Float,
    difficulty: Difficulty,
    surface: Option(String),
    geometry: List(Point),
    near_beach: Option(NearAnchor),
    near_lake: Option(NearAnchor),
  )
}

/// A trail with fewer than two points cannot be drawn.
pub fn drawable(trail: Trail) -> Bool {
  case trail.geometry {
    [_, _, ..] -> True
    _ -> False
  }
}

fn anchor_decoder() -> Decoder(NearAnchor) {
  use name <- decode.field("name", decode.string)
  use distance_km <- decode.field("distance_km", decoders.number())
  decode.success(NearAnchor(name:, distance_km:))
}

/// A `[lat, lon]` pair.
fn lat_lon_decoder() -> Decoder(Point) {
  decode.list(decoders.number())
  |> decode.then(fn(pair) {
    case pair {
      [lat, lon] -> decode.success(geo.Point(lat:, lon:))
      _ -> decode.failure(geo.Point(0.0, 0.0), "a [lat, lon] pair")
    }
  })
}

pub fn decoder() -> Decoder(Trail) {
  use name <- decode.field("name", decode.string)
  use length_km <- decode.field("length_km", decoders.number())
  use difficulty <- decode.field("difficulty", difficulty.decoder())
  use surface <- decode.field("surface", decode.optional(decode.string))
  use geometry <- decode.field("geometry", decode.list(lat_lon_decoder()))
  use near_beach <- decode.field(
    "near_beach",
    decode.optional(anchor_decoder()),
  )
  use near_lake <- decode.field("near_lake", decode.optional(anchor_decoder()))
  decode.success(Trail(
    name:,
    length_km:,
    difficulty:,
    surface:,
    geometry:,
    near_beach:,
    near_lake:,
  ))
}
