//// Points on the earth: great-circle distance and compass points.

import gleam/float
import gleam/int
import gleam/list
import gleam/result
import marola/math

pub type Point {
  Point(lat: Float, lon: Float)
}

const earth_radius_km = 6371.0

fn radians(degrees: Float) -> Float {
  degrees *. math.pi /. 180.0
}

/// The great-circle distance in km. The operations keep the order of app.js
/// `haversineKm`, so both agree to the last digits.
pub fn haversine_km(a: Point, b: Point) -> Float {
  let d_lat = radians(b.lat -. a.lat)
  let d_lon = radians(b.lon -. a.lon)
  let la1 = radians(a.lat)
  let la2 = radians(b.lat)
  let h =
    math.sin(d_lat /. 2.0)
    *. math.sin(d_lat /. 2.0)
    +. math.cos(la1)
    *. math.cos(la2)
    *. math.sin(d_lon /. 2.0)
    *. math.sin(d_lon /. 2.0)
  // Rounding can push h just past 1 for antipodes; asin would fail there.
  let root = float.square_root(float.min(h, 1.0)) |> result.unwrap(0.0)
  2.0 *. earth_radius_km *. math.asin(root)
}

const compass_points = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]

/// The catalog key suffix (`dir.<this>`) of a bearing in degrees, to the
/// nearest of eight points.
pub fn compass_key(degrees: Float) -> String {
  let index = float.truncate(float.floor(degrees /. 45.0 +. 0.5))
  let wrapped = case int.modulo(index, 8) {
    Ok(i) -> i
    Error(Nil) -> 0
  }
  case list.drop(compass_points, wrapped) {
    [first, ..] -> first
    [] -> "n"
  }
}
