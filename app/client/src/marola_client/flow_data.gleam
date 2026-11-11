//// The flow layer's data: the wind or wave field between the beaches, at the
//// hour on the slider. The field is `marola/flow`'s; this turns it into the
//// flat arrays `flow_layer_ffi.mjs` samples every frame.

import gleam/dict
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import marola/beach
import marola/flow
import marola_client/config
import marola_client/model.{type Model} as mdl

/// The top of the colour ramp: km/h of wind, metres of wave.
fn max_of(layer: mdl.Layer) -> Float {
  case layer {
    mdl.Wind -> 40.0
    _ -> 3.0
  }
}

fn readings(model: Model, layer: mdl.Layer) -> List(flow.Reading) {
  case model.board {
    None -> []
    Some(board) ->
      list.filter_map(board.beaches, fn(b) {
        case beach.hour_entry(b, beach.shown(b, model.selection)) {
          None -> Error(Nil)
          Some(entry) ->
            // The directions are the board's, taken at the best hour.
            Ok(case layer {
              mdl.Wind ->
                flow.Reading(b.lon, b.lat, entry.wind_kmh, b.sea.wind_dir_deg)
              _ -> flow.Reading(b.lon, b.lat, entry.wave_m, b.sea.wave_dir_deg)
            })
        }
      })
  }
}

fn rounded(values: List(Float)) -> Json {
  json.array(values, fn(v) { json.float(float.to_precision(v, 4)) })
}

fn cells(field: flow.Field) -> List(flow.Cell) {
  int.range(from: 0, to: field.w * field.h, with: [], run: fn(acc, n) {
    case dict.get(field.cells, n) {
      Ok(cell) -> [cell, ..acc]
      Error(Nil) -> [flow.Cell(0.0, 0.0, 0.0, 0.0), ..acc]
    }
  })
  |> list.reverse
}

/// `null` when the layer is neither wind nor waves, or no beach has both numbers.
pub fn json(model: Model) -> String {
  case model.layer {
    mdl.Wind | mdl.Waves ->
      case flow.build_field(readings(model, model.layer), max_of(model.layer)) {
        Error(Nil) -> "null"
        Ok(field) -> {
          let all = cells(field)
          json.object([
            #("kind", json.string(mdl.layer_key(model.layer))),
            #("w", json.int(field.w)),
            #("h", json.int(field.h)),
            #("x0", json.float(field.x0)),
            #("x1", json.float(field.x1)),
            #("y0", json.float(field.y0)),
            #("y1", json.float(field.y1)),
            #("u", rounded(list.map(all, fn(c) { c.u }))),
            #("v", rounded(list.map(all, fn(c) { c.v }))),
            #("m", rounded(list.map(all, fn(c) { c.m }))),
            #("a", rounded(list.map(all, fn(c) { c.a }))),
            #("ramp", json.array(ramp(model.layer), json.string)),
          ])
          |> json.to_string
        }
      }
    _ -> "null"
  }
}

fn ramp(layer: mdl.Layer) -> List(String) {
  case layer {
    mdl.Wind -> config.wind_ramp
    _ -> config.wave_ramp
  }
}
