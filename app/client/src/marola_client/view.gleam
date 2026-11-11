//// The whole page, from the model. The map itself is not drawn here: its
//// `div` stays empty, and MapLibre fills it.

import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{attribute, class}
import lustre/element.{type Element}
import lustre/element/html
import marola_client/model.{type Model} as mdl
import marola_client/msg.{type Msg}
import marola_client/view/bar
import marola_client/view/card
import marola_client/view/footer
import marola_client/view/layers
import marola_client/view/list as beach_list
import marola_client/view/nav
import marola_client/view/sos
import marola_client/view/text.{hidden, t}
import marola_client/view/trails_view

/// The map's note when it could not start: the list carries the page.
fn map_note(model: Model) -> Element(Msg) {
  case model.map {
    mdl.MapFailed(key) ->
      html.p(
        [
          attribute.id("map-note"),
          class("map-note"),
          attribute("aria-live", "polite"),
        ],
        [html.text(t(model, key))],
      )
    _ ->
      html.p([attribute.id("map-note"), class("map-note"), ..hidden(True)], [])
  }
}

/// The classes the stylesheet reads to dim the dots under the water layer or
/// hide them. They sit on `main`, not on `#map`: MapLibre owns the map's classes.
fn main_class(model: Model) -> String {
  "main"
  <> case model.layer {
    mdl.Water -> " layer-water"
    _ -> ""
  }
  <> case model.show_beaches {
    True -> ""
    False -> " no-beaches"
  }
}

fn card_slot(model: Model) -> Element(Msg) {
  case trails_view.picked(model) {
    Some(route) -> trails_view.card(model, route)
    None -> card.view(model)
  }
}

/// A map that failed to start has no layers to pick.
fn rail(model: Model) -> List(Element(Msg)) {
  case model.map {
    mdl.MapFailed(_) -> []
    _ -> [layers.rail(model), layers.key(model)]
  }
}

fn stage(model: Model) -> Element(Msg) {
  html.main(
    [class(main_class(model))],
    list.flatten([
      [
        html.div(
          [
            attribute.id("map"),
            attribute("role", "application"),
            attribute("aria-label", t(model, "map.label")),
          ],
          [],
        ),
      ],
      rail(model),
      sos.view(model),
      [
        map_note(model),
        beach_list.view(model),
        trails_view.panel(model),
        card_slot(model),
      ],
    ]),
  )
}

pub fn view(model: Model) -> Element(Msg) {
  case model.catalogs_pending > 0 {
    True -> html.p([class("nojs")], [html.text("…")])
    False ->
      element.fragment([
        nav.view(model),
        bar.header(model),
        bar.hourbar(model),
        stage(model),
        footer.view(model),
      ])
  }
}
