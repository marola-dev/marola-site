//// The rail of map layers and the key of the one on show.

import gleam/list
import gleam/option.{Some}
import lustre/attribute.{attribute, class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import marola/datefmt
import marola_client/model.{type Layer, type Model} as mdl
import marola_client/msg.{type Msg}
import marola_client/raster
import marola_client/view/text.{expanded, icon, pressed, t}

fn icon_of(layer: Layer) -> String {
  case layer {
    mdl.Wind -> "wind"
    mdl.Waves -> "waves"
    mdl.Water -> "droplet"
    mdl.Clouds -> "cloud"
    mdl.Sst -> "thermometer"
    mdl.Anomaly -> "pulse"
    mdl.Elnino -> "globe"
    mdl.Off -> "list"
  }
}

/// A layer that is not built shows as "(soon)" and cannot be pressed.
fn layer_button(model: Model, layer: Layer) -> Element(Msg) {
  let key = mdl.layer_key(layer)
  let enabled = mdl.layer_enabled(layer)
  let label = case enabled {
    True -> t(model, "flow." <> key)
    False -> t(model, "flow." <> key <> "_soon")
  }
  html.button(
    [
      attribute.type_("button"),
      attribute("data-layer", key),
      attribute.title(label),
      pressed(model.layer == layer),
      ..case enabled {
        True -> [event.on_click(msg.LayerPressed(layer))]
        False -> [class("soon"), attribute.disabled(True)]
      }
    ],
    [icon(icon_of(layer)), html.span([], [html.text(label)])],
  )
}

fn toggle(
  model: Model,
  key: String,
  icon_name: String,
  on: Bool,
  message: Msg,
) -> Element(Msg) {
  html.button(
    [
      attribute.type_("button"),
      attribute("data-toggle", key),
      attribute.title(t(model, "flow." <> key)),
      pressed(on),
      event.on_click(message),
    ],
    [icon(icon_name), html.span([], [html.text(t(model, "flow." <> key))])],
  )
}

pub fn rail(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.id("flow"),
      class("flow"),
      attribute("role", "group"),
      attribute("aria-label", t(model, "flow.label")),
    ],
    [
      html.div([class("layers")], [
        toggle(model, "beaches", "pin", model.show_beaches, msg.BeachesToggled),
        toggle(
          model,
          "trails",
          "footprints",
          model.show_trails,
          msg.TrailsToggled,
        ),
        html.button(
          [
            attribute.type_("button"),
            attribute("aria-controls", "trails-panel"),
            attribute("data-panel", "trails"),
            attribute.title(t(model, "trails.list")),
            expanded(model.panel == mdl.TrailList),
            event.on_click(msg.TrailPanelToggled),
          ],
          [
            icon("list"),
            html.span([], [html.text(t(model, "trails.list"))]),
          ],
        ),
        html.span([class("sep"), attribute("aria-hidden", "true")], []),
        ..list.append(list.map(mdl.layers, layer_button(model, _)), [
          html.button(
            [
              attribute.type_("button"),
              class("soon"),
              attribute.disabled(True),
              attribute.title(t(model, "flow.bathymetry_soon")),
            ],
            [
              icon("mountain"),
              html.span([], [html.text(t(model, "flow.bathymetry_soon"))]),
            ],
          ),
        ])
      ]),
    ],
  )
}

fn ends(left: String, right: String) -> Element(Msg) {
  html.span([class("ends")], [
    html.span([], [html.text(left)]),
    html.span([], [html.text(right)]),
  ])
}

fn ramp(kind: String) -> Element(Msg) {
  html.span([class("ramp " <> kind), attribute("aria-hidden", "true")], [])
}

/// The day of the imagery, which is not the day of the board.
fn when(model: Model, layer: Layer) -> String {
  case raster.of_layer(layer), model.board {
    Some(r), Some(board) -> raster.day(r, board.today)
    _, _ -> ""
  }
}

/// The key under the rail: what the colours mean, for the layer on show.
pub fn key(model: Model) -> Element(Msg) {
  let shown = case model.layer {
    mdl.Off -> []
    mdl.Wind -> [
      ramp("wind"),
      ends("0", "40 km/h"),
      html.span([], [html.text(t(model, "flow.key_wind"))]),
    ]
    mdl.Waves -> [
      ramp("waves"),
      ends("0", "3 m"),
      html.span([], [html.text(t(model, "flow.key_waves"))]),
    ]
    mdl.Water -> [html.span([], [html.text(t(model, "flow.key_water"))])]
    mdl.Clouds -> [dated(model, "flow.key_clouds", mdl.Clouds)]
    mdl.Sst -> [
      ramp("sst"),
      ends(t(model, "flow.cold"), t(model, "flow.warm")),
      dated(model, "flow.key_sst", mdl.Sst),
    ]
    mdl.Anomaly -> [
      ramp("anomaly"),
      ends(t(model, "flow.colder"), t(model, "flow.warmer")),
      dated(model, "flow.key_anomaly", mdl.Anomaly),
    ]
    mdl.Elnino -> [
      ramp("anomaly"),
      ends(t(model, "flow.colder"), t(model, "flow.warmer")),
      html.span([], [html.text(t(model, "flow.key_elnino"))]),
    ]
  }
  html.div([attribute.id("flowkeys"), class("flowkeys")], case shown {
    [] -> []
    parts -> [
      html.p(
        [class("flowkey"), attribute("data-key", mdl.layer_key(model.layer))],
        parts,
      ),
    ]
  })
}

fn dated(model: Model, key: String, layer: Layer) -> Element(Msg) {
  let day = when(model, layer)
  let label = t(model, key)
  html.span([], [
    html.text(case day {
      "" -> label
      _ -> label <> " " <> datefmt.short(day, model.loc.language)
    }),
  ])
}
