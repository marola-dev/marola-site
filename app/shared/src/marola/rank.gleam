//// The list's two orders. The old `ranked()` wrote `_km` into the board; here
//// the distance travels beside the beach and the board stays as it was.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import marola/beach.{type Beach, type Selection}
import marola/geo.{type Point}

/// Nearest first, each with its distance in km.
pub fn by_distance(beaches: List(Beach), here: Point) -> List(#(Beach, Float)) {
  beaches
  |> list.map(fn(b) { #(b, geo.haversine_km(here, geo.Point(b.lat, b.lon))) })
  |> list.sort(fn(a, b) { float.compare(a.1, b.1) })
}

/// Best score first at the hour on show; a beach dark then goes last.
pub fn by_score(beaches: List(Beach), selection: Selection) -> List(Beach) {
  let score = fn(b) {
    case beach.shown(b, selection) {
      Some(s) -> s.score
      None -> -1
    }
  }
  list.sort(beaches, fn(a, b) { int.compare(score(b), score(a)) })
}
