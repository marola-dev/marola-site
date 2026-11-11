//// Web Mercator in unit space (0..1 across the world), as flow.js draws in.

import marola/math

/// Latitude where the projection's log would reach infinity; stays finite on Erlang.
const lat_limit = 89.999999

pub fn x(lon: Float) -> Float {
  { lon +. 180.0 } /. 360.0
}

pub fn y(lat: Float) -> Float {
  let clamped = case lat >. lat_limit, lat <. 0.0 -. lat_limit {
    True, _ -> lat_limit
    _, True -> 0.0 -. lat_limit
    _, _ -> lat
  }
  let s = math.sin(clamped *. math.pi /. 180.0)
  0.5 -. math.ln({ 1.0 +. s } /. { 1.0 -. s }) /. { 4.0 *. math.pi }
}

pub fn lon_of(x: Float) -> Float {
  x *. 360.0 -. 180.0
}

pub fn lat_of(y: Float) -> Float {
  360.0
  /. math.pi
  *. math.atan(math.exp({ 1.0 -. 2.0 *. y } *. math.pi))
  -. 90.0
}
