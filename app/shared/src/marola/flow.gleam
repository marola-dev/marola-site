//// The wind and wave field of the flow layer, interpolated from the beaches'
//// own readings (no weather grid is fetched). A port of flow.js `buildField`
//// and `sample`. flow.js keeps the grid in Float32Array, so its values are
//// rounded to 32 bits; these stay in 64 bits and differ by about 1e-7.

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import marola/math
import marola/mercator

const km_per_deg = 111.32

/// The field reaches this far past the outermost beach.
const pad_km = 30.0

/// It fades out over about this distance from the nearest one.
const reach_km = 18.0

pub const grid = 96

/// One beach reading. `dir` is the degrees the flow comes FROM (Open-Meteo's
/// convention). A reading without both numbers is left out.
pub type Reading {
  Reading(lon: Float, lat: Float, mag: Option(Float), dir: Option(Float))
}

/// A cell: `u` and `v` east and north in units of `mag`, `m` is mag over max
/// (0..1) and `a` is how close the nearest beach is (0..1).
pub type Cell {
  Cell(u: Float, v: Float, m: Float, a: Float)
}

/// A `grid` by `grid` field in mercator space.
pub type Field {
  Field(
    w: Int,
    h: Int,
    x0: Float,
    x1: Float,
    y0: Float,
    y1: Float,
    max: Float,
    cells: Dict(Int, Cell),
  )
}

type Vec {
  Vec(x: Float, y: Float, u: Float, v: Float, mag: Float)
}

/// `Error(Nil)` when no reading has both numbers.
pub fn build_field(readings: List(Reading), max: Float) -> Result(Field, Nil) {
  let pts =
    list.filter_map(readings, fn(r) {
      case r.mag, r.dir {
        Some(mag), Some(dir) -> Ok(#(r.lon, r.lat, mag, dir))
        _, _ -> Error(Nil)
      }
    })
  case pts {
    [] -> Error(Nil)
    _ -> Ok(field(pts, max))
  }
}

fn field(pts: List(#(Float, Float, Float, Float)), max: Float) -> Field {
  let count = int.to_float(list.length(pts))
  let lat0 = list.fold(pts, 0.0, fn(sum, p) { sum +. p.1 }) /. count
  let kx = km_per_deg *. math.cos(lat0 *. math.pi /. 180.0)
  let ky = km_per_deg
  let lons = list.map(pts, fn(p) { p.0 })
  let lats = list.map(pts, fn(p) { p.1 })
  let min_lon = list_min(lons) -. pad_km /. kx
  let max_lon = list_max(lons) +. pad_km /. kx
  let min_lat = list_min(lats) -. pad_km /. ky
  let max_lat = list_max(lats) +. pad_km /. ky
  let x0 = mercator.x(min_lon)
  let x1 = mercator.x(max_lon)
  let y0 = mercator.y(max_lat)
  let y1 = mercator.y(min_lat)
  let vecs =
    list.map(pts, fn(p) {
      // The board says where the flow comes from; particles go the other way.
      let to = { p.3 +. 180.0 } *. math.pi /. 180.0
      Vec(p.0 *. kx, p.1 *. ky, math.sin(to) *. p.2, math.cos(to) *. p.2, p.2)
    })
  let cells =
    int.range(from: 0, to: grid * grid, with: dict.new(), run: fn(acc, n) {
      let j = n / grid
      let i = n % grid
      let lat =
        mercator.lat_of(
          y0 +. { y1 -. y0 } *. { int.to_float(j) +. 0.5 } /. int.to_float(grid),
        )
      let lon =
        mercator.lon_of(
          x0 +. { x1 -. x0 } *. { int.to_float(i) +. 0.5 } /. int.to_float(grid),
        )
      dict.insert(acc, n, cell(vecs, lon *. kx, lat *. ky, max))
    })
  Field(grid, grid, x0, x1, y0, y1, max, cells)
}

/// Inverse-distance weighting of every reading at one point.
fn cell(vecs: List(Vec), px: Float, py: Float, max: Float) -> Cell {
  let #(sw, su, sv, sm, dmin) =
    list.fold(vecs, #(0.0, 0.0, 0.0, 0.0, float_max), fn(acc, vec) {
      let dx = px -. vec.x
      let dy = py -. vec.y
      let d2 = dx *. dx +. dy *. dy
      let w = 1.0 /. { d2 +. 0.25 }
      #(
        acc.0 +. w,
        acc.1 +. w *. vec.u,
        acc.2 +. w *. vec.v,
        acc.3 +. w *. vec.mag,
        float.min(acc.4, d2),
      )
    })
  Cell(
    u: su /. sw,
    v: sv /. sw,
    m: float.min(1.0, sm /. sw /. max),
    a: math.exp(0.0 -. dmin /. { reach_km *. reach_km }),
  )
}

const float_max = 1.7976931348623157e308

fn list_min(values: List(Float)) -> Float {
  list.fold(values, float_max, float.min)
}

fn list_max(values: List(Float)) -> Float {
  list.fold(values, 0.0 -. float_max, float.max)
}

/// Bilinear sample at a mercator point, or `Error(Nil)` outside the field.
pub fn sample(f: Field, x: Float, y: Float) -> Result(Cell, Nil) {
  let w = int.to_float(f.w)
  let h = int.to_float(f.h)
  let gx = { x -. f.x0 } /. { f.x1 -. f.x0 } *. w -. 0.5
  let gy = { y -. f.y0 } /. { f.y1 -. f.y0 } *. h -. 0.5
  case gx >=. -0.5 && gy >=. -0.5 && gx <=. w -. 0.5 && gy <=. h -. 0.5 {
    False -> Error(Nil)
    True -> {
      let i0 = int.max(0, int.min(f.w - 1, float.truncate(float.floor(gx))))
      let j0 = int.max(0, int.min(f.h - 1, float.truncate(float.floor(gy))))
      let i1 = int.min(f.w - 1, i0 + 1)
      let j1 = int.min(f.h - 1, j0 + 1)
      let tx = float.clamp(gx -. int.to_float(i0), 0.0, 1.0)
      let ty = float.clamp(gy -. int.to_float(j0), 0.0, 1.0)
      let at = fn(pick: fn(Cell) -> Float) {
        let get = fn(j, i) { pick(cell_at(f, j * f.w + i)) }
        let a = get(j0, i0) *. { 1.0 -. tx } +. get(j0, i1) *. tx
        let b = get(j1, i0) *. { 1.0 -. tx } +. get(j1, i1) *. tx
        a *. { 1.0 -. ty } +. b *. ty
      }
      Ok(Cell(
        u: at(fn(c) { c.u }),
        v: at(fn(c) { c.v }),
        m: at(fn(c) { c.m }),
        a: at(fn(c) { c.a }),
      ))
    }
  }
}

fn cell_at(f: Field, n: Int) -> Cell {
  case dict.get(f.cells, n) {
    Ok(c) -> c
    Error(Nil) -> Cell(0.0, 0.0, 0.0, 0.0)
  }
}
