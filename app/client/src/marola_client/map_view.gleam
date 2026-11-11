//// What the map shows, as one JSON text for `maplibre_ffi.mjs`: the beach
//// dots, the water-sampling points, the visitor, the satellite layer and the
//// trail visibility. The map keeps the last text of each part and redraws only
//// the part that changed.

import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import marola/aspects
import marola/band
import marola/beach.{type Beach}
import marola/board.{type Board}
import marola/geo
import marola/i18n
import marola/water
import marola_client/aspects_view
import marola_client/dom.{type Dom}
import marola_client/model.{type Model} as mdl
import marola_client/raster

/// The west, south, east and north edges of the beaches, or none.
pub fn beach_bounds(board: Board) -> Option(#(Float, Float, Float, Float)) {
  case board.beaches {
    [] -> None
    [first, ..rest] ->
      Some(
        list.fold(rest, #(first.lon, first.lat, first.lon, first.lat), fn(b, x) {
          #(
            float.min(b.0, x.lon),
            float.min(b.1, x.lat),
            float.max(b.2, x.lon),
            float.max(b.3, x.lat),
          )
        }),
      )
  }
}

type Marker {
  Marker(
    key: String,
    lon: Float,
    lat: Float,
    label: Option(String),
    node: Dom,
    tip: Dom,
    tip_class: String,
    offset: Int,
    click: Option(String),
  )
}

fn marker_json(m: Marker) -> Json {
  json.object([
    #("key", json.string(m.key)),
    #("lon", json.float(m.lon)),
    #("lat", json.float(m.lat)),
    #("label", json.nullable(m.label, json.string)),
    #("node", dom.to_json(m.node)),
    #("tip", dom.to_json(m.tip)),
    #("tip_class", json.string(m.tip_class)),
    #("offset", json.int(m.offset)),
    #("click", json.nullable(m.click, json.string)),
  ])
}

fn num(n: Float) -> String {
  float.to_string(n)
}

/// A beach is a dot in its score colour: a white ring keeps neighbours apart
/// where beaches crowd, and the picked one grows into a badge with its number.
/// The colour is a class, never an inline style: the CSP blocks `style=`.
pub fn wave_icon(
  band_class: String,
  selected: Bool,
  score: Option(Int),
) -> Dom {
  let size = case selected {
    True -> 32.0
    False -> 16.0
  }
  let r = size /. 2.0
  let label = case selected, score {
    True, Some(s) -> [
      dom.svg(
        "text",
        [
          #("x", "16"),
          #("y", "20.5"),
          #("text-anchor", "middle"),
          #("font-size", "13"),
          #("font-weight", "600"),
          #("class", case band_class {
            "c40" -> "num dark"
            _ -> "num"
          }),
        ],
        [dom.text(int.to_string(s))],
      ),
    ]
    _, _ -> []
  }
  dom.svg(
    "svg",
    [
      #("viewBox", "0 0 " <> num(size) <> " " <> num(size)),
      #("width", num(size)),
      #("height", num(size)),
      #("aria-hidden", "true"),
    ],
    [
      dom.svg(
        "circle",
        [
          #("cx", num(r)),
          #("cy", num(r)),
          #("r", num(r -. 0.5)),
          #("fill", "#1d2733"),
        ],
        [],
      ),
      dom.svg(
        "circle",
        [
          #("cx", num(r)),
          #("cy", num(r)),
          #("r", num(r -. 2.0)),
          #("class", "dot f-" <> band_class),
          #("stroke", "#fff"),
          #("stroke-width", "2"),
        ],
        [],
      ),
      ..label
    ],
  )
}

fn beach_marker(model: Model, b: Beach) -> Marker {
  let shown = beach.shown(b, model.selection)
  let score = option.map(shown, fn(s) { s.score })
  let selected = model.selected == Some(b.name)
  let past = case shown, model.board {
    Some(s), Some(board) -> board.is_past(board, s.h)
    _, _ -> False
  }
  let class =
    "wave"
    <> case selected {
      True -> " selected"
      False -> ""
    }
    <> case past {
      True -> " past"
      False -> ""
    }
  let band_class = band.css_class(band.of_score(score, b.water.unfit))
  let tip = aspects.of(b, shown, model.loc)
  Marker(
    key: b.name,
    lon: b.lon,
    lat: b.lat,
    label: Some(b.name),
    node: dom.el("div", [#("class", class)], [
      wave_icon(band_class, selected, score),
    ]),
    tip: dom.el("div", [], aspects_view.children(tip)),
    tip_class: "aspects",
    offset: case selected {
      True -> 18
      False -> 10
    },
    click: Some("beach"),
  )
}

/// Lucide's droplet, so a sampling point never reads as a beach dot;
/// `style.css` fills it by band.
pub fn drop() -> Dom {
  let d =
    "M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z"
  dom.svg(
    "svg",
    [
      #("viewBox", "0 0 24 24"),
      #("aria-hidden", "true"),
      #("focusable", "false"),
    ],
    [
      dom.svg("path", [#("class", "rim"), #("d", d)], []),
      dom.svg("path", [#("class", "fill"), #("d", d)], []),
    ],
  )
}

fn water_marker(model: Model, p: water.Point) -> Marker {
  let band_class = band.css_class(water.condition_band(p.condition))
  let text =
    p.point
    <> " ("
    <> p.location
    <> "): "
    <> water.condition_label(p.condition, model.loc)
    <> ", "
    <> p.sampled_on
  Marker(
    key: p.point,
    lon: p.lon,
    lat: p.lat,
    label: Some(p.point),
    node: dom.el("div", [#("class", "wpoint " <> band_class)], [drop()]),
    tip: dom.el("span", [#("class", "water")], [dom.text(text)]),
    tip_class: "",
    offset: 8,
    click: None,
  )
}

fn beaches(model: Model) -> List(Beach) {
  case model.board {
    Some(board) -> board.beaches
    None -> []
  }
}

fn selected_beach(model: Model) -> Option(Beach) {
  case model.selected {
    None -> None
    Some(name) ->
      list.find(beaches(model), fn(b) { b.name == name }) |> option.from_result
  }
}

/// The water layer shows every beach's sampling points; the others only the
/// selected beach's.
fn water_points(model: Model) -> List(water.Point) {
  let shown = case model.layer, selected_beach(model) {
    mdl.Water, _ -> beaches(model)
    _, Some(b) -> [b]
    _, None -> []
  }
  list.flat_map(shown, fn(b) { b.water.points })
}

fn here_marker(model: Model) -> List(Marker) {
  case model.here {
    None -> []
    Some(geo.Point(lat, lon)) -> [
      Marker(
        key: "here",
        lon:,
        lat:,
        label: None,
        node: dom.el("div", [#("class", "here")], []),
        tip: dom.el("span", [], [dom.text(i18n.t(model.loc, "near.you", []))]),
        tip_class: "",
        offset: 8,
        click: None,
      ),
    ]
  }
}

fn raster_json(model: Model) -> Json {
  case raster.of_layer(model.layer), model.board {
    Some(r), Some(board) -> raster.spec(r, board.today)
    _, _ -> json.null()
  }
}

fn nino_json(model: Model) -> Json {
  case model.layer {
    mdl.Elnino ->
      json.array(raster.nino34(), fn(p) { json.array([p.0, p.1], json.int) })
    _ -> json.null()
  }
}

pub fn sync_json(model: Model) -> String {
  json.object([
    #(
      "markers",
      json.array(list.map(beaches(model), beach_marker(model, _)), marker_json),
    ),
    #(
      "points",
      json.array(
        list.map(water_points(model), water_marker(model, _)),
        marker_json,
      ),
    ),
    #("here", json.array(here_marker(model), marker_json)),
    #("raster", raster_json(model)),
    #("nino", nino_json(model)),
    #(
      "trails",
      json.object([
        #("visible", json.bool(model.show_trails)),
        #("selected", json.int(option.unwrap(model.trail_selected, -1))),
      ]),
    ),
  ])
  |> json.to_string
}
