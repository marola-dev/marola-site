//// The colour ramp texture of the flow layer: evenly spaced hex stops as 256 RGBA texels.

import gleam/float
import gleam/int
import gleam/list
import gleam/string

type Rgb =
  #(Int, Int, Int)

/// "#rrggbb" or "rrggbb"; anything else is white.
pub fn hex_rgb(hex: String) -> #(Int, Int, Int) {
  let digits = string.trim(hex) |> string.remove_prefix("#")
  let chars = string.to_graphemes(digits)
  case list.length(chars) == 6 && list.all(chars, is_hex) {
    True ->
      case chars {
        [a, b, c, d, e, f] -> #(byte(a, b), byte(c, d), byte(e, f))
        _ -> white
      }
    False -> white
  }
}

const white = #(255, 255, 255)

fn is_hex(char: String) -> Bool {
  string.contains("0123456789abcdefABCDEF", char)
}

fn byte(high: String, low: String) -> Int {
  case int.base_parse(high <> low, 16) {
    Ok(value) -> value
    Error(Nil) -> 255
  }
}

/// 1024 bytes, R G B A per texel. Needs two stops or more.
pub fn pixels(stops: List(String)) -> Result(List(Int), Nil) {
  let rgb = list.map(stops, hex_rgb)
  case list.length(rgb) < 2 {
    True -> Error(Nil)
    False ->
      Ok(
        list.flat_map(
          list.index_map(list.repeat(0, 256), fn(_, i) { i }),
          fn(i) { texel(rgb, i) },
        ),
      )
  }
}

fn texel(rgb: List(Rgb), i: Int) -> List(Int) {
  let last = list.length(rgb) - 1
  let t = int.to_float(i) /. 255.0 *. int.to_float(last)
  let k = int.min(last - 1, float.truncate(float.floor(t)))
  let f = t -. int.to_float(k)
  case list.drop(rgb, k) {
    [#(r0, g0, b0), #(r1, g1, b1), ..] -> [
      mix(r0, r1, f),
      mix(g0, g1, f),
      mix(b0, b1, f),
      255,
    ]
    _ -> [255, 255, 255, 255]
  }
}

/// `Math.round(a * (1 - f) + b * f)`: halves round up.
fn mix(a: Int, b: Int, f: Float) -> Int {
  let value = int.to_float(a) *. { 1.0 -. f } +. int.to_float(b) *. f
  float.truncate(float.floor(value +. 0.5))
}
