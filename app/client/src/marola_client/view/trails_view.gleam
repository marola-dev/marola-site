//// The trails panel (routes grouped by bairro) and the card of a picked route.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{attribute, class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import marola/difficulty
import marola/fmt
import marola/html as safe
import marola/i18n
import marola/trails.{type Group, type Route, type Trails}
import marola_client/model.{type Model} as mdl
import marola_client/msg.{type Msg}
import marola_client/view/text.{hidden, t, ta}

fn difficulty_text(model: Model, route: Route) -> String {
  case route.difficulty {
    difficulty.Hiking -> t(model, "trails.hiking")
    difficulty.MountainHiking -> t(model, "trails.mountain_hiking")
    difficulty.Unrated -> t(model, "trails.unrated")
    difficulty.Unknown(raw) -> raw
  }
}

fn length_text(model: Model, route: Route) -> String {
  fmt.value(model.loc, Some(route.length_km), " km", 1)
}

fn route_item(model: Model, id: Int, route: Route) -> Element(Msg) {
  html.li([], [
    html.button(
      [
        attribute.type_("button"),
        attribute("data-trail", int.to_string(id)),
        class("trail"),
        expanded_if(model.trail_selected == Some(id)),
        event.on_click(msg.TrailChosen(id, True)),
      ],
      [
        html.span([class("score " <> difficulty_band(route))], [
          html.text(difficulty_text(model, route)),
        ]),
        html.text(route.name <> " "),
        html.span([class("dist")], [html.text(length_text(model, route))]),
      ],
    ),
  ])
}

fn expanded_if(on: Bool) -> attribute.Attribute(Msg) {
  attribute("aria-current", case on {
    True -> "true"
    False -> "false"
  })
}

fn difficulty_band(route: Route) -> String {
  case route.difficulty {
    difficulty.Hiking -> "c70"
    difficulty.MountainHiking -> "c40"
    _ -> "cna"
  }
}

/// The groups with the position of each route, which is its id on the map.
fn numbered(groups: List(Group)) -> List(#(Group, Int)) {
  list.fold(groups, #([], 0), fn(acc, group) {
    #([#(group, acc.1), ..acc.0], acc.1 + list.length(group.routes))
  }).0
  |> list.reverse
}

fn group_view(model: Model, entry: #(Group, Int)) -> Element(Msg) {
  let #(group, first) = entry
  let name = option.unwrap(group.bairro, t(model, "trails.no_bairro"))
  html.section([class("trail-group")], [
    html.h3([], [html.text(name)]),
    html.ul(
      [],
      list.index_map(group.routes, fn(route, i) {
        route_item(model, first + i, route)
      }),
    ),
  ])
}

fn note(found: Trails) -> List(Element(Msg)) {
  case found.note {
    Some(text) -> [html.p([class("trail-note")], [html.text(text)])]
    None -> []
  }
}

/// The footer of the panel: the municipality, and where the lines come from.
fn footer(model: Model, found: Trails) -> Element(Msg) {
  let ibge = case found.ibge_municipality {
    Some(code) -> [
      html.p([], [
        html.text(ta(model, "trails.ibge", [i18n.arg("code", code)])),
      ]),
    ]
    None -> []
  }
  let licence = case found.licence {
    Some(l) -> ", " <> l
    None -> ""
  }
  html.footer([class("trail-foot")], [
    html.p([], [
      html.text(
        ta(model, "trails.source", [
          i18n.arg("source", found.source <> licence),
        ]),
      ),
    ]),
    ..ibge
  ])
}

fn panel_body(model: Model) -> List(Element(Msg)) {
  case model.trails_file, mdl.trails(model) {
    mdl.TrailsPending, _ -> [
      html.p([], [html.text(t(model, "status.loading"))]),
    ]
    _, None -> [html.p([], [html.text(t(model, "trails.empty"))])]
    _, Some(found) ->
      case trails.is_empty(found) {
        // An area with no routes says why, never an empty panel.
        True ->
          case found.note {
            Some(_) -> note(found)
            None -> [html.p([], [html.text(t(model, "trails.empty"))])]
          }
          |> list.append([footer(model, found)])
        False ->
          list.flatten([
            note(found),
            list.map(numbered(found.groups), group_view(model, _)),
            [footer(model, found)],
          ])
      }
  }
}

pub fn panel(model: Model) -> Element(Msg) {
  html.aside(
    [
      attribute.id("trails-panel"),
      class("list trails"),
      attribute("aria-label", t(model, "flow.trails")),
      ..hidden(model.panel != mdl.TrailList)
    ],
    [html.h2([], [html.text(t(model, "flow.trails"))]), ..panel_body(model)],
  )
}

fn way_link(model: Model, id: Int) -> List(Element(Msg)) {
  case safe.safe_href(trails.way_url(id)) {
    Ok(href) -> [
      html.a(
        [
          attribute.href(href),
          attribute.target("_blank"),
          attribute.rel("noopener"),
        ],
        [
          html.text(
            ta(model, "trails.way", [i18n.arg("id", int.to_string(id))]),
          ),
        ],
      ),
    ]
    Error(Nil) -> []
  }
}

fn row(model: Model, key: String, body: List(Element(Msg))) {
  [html.dt([], [html.text(t(model, key))]), html.dd([], body)]
}

pub fn card(model: Model, route: Route) -> Element(Msg) {
  let surface = case route.surface {
    Some(s) -> row(model, "trails.surface", [html.text(s)])
    None -> []
  }
  let ways = case route.osm_ways {
    [] -> []
    ids ->
      row(
        model,
        "trails.ways",
        list.index_map(ids, fn(id, i) {
          case i {
            0 -> way_link(model, id)
            _ -> [html.text(" · "), ..way_link(model, id)]
          }
        })
          |> list.flatten,
      )
  }
  html.section(
    [
      attribute.id("card"),
      class("card trail-card"),
      attribute("aria-live", "polite"),
    ],
    [
      html.button(
        [
          class("close"),
          attribute.type_("button"),
          attribute("aria-label", t(model, "card.close")),
          event.on_click(msg.CardClosed),
        ],
        [html.text("×")],
      ),
      html.h2([], [html.text(route.name)]),
      html.dl(
        [],
        list.flatten([
          row(model, "trails.length", [html.text(length_text(model, route))]),
          row(model, "trails.difficulty", [
            html.text(difficulty_text(model, route)),
          ]),
          surface,
          ways,
        ]),
      ),
    ],
  )
}

/// The route the card shows, if one is picked.
pub fn picked(model: Model) -> Option(Route) {
  case model.trail_selected, mdl.trails(model) {
    Some(id), Some(found) -> trails.route_at(found, id) |> option.from_result
    _, _ -> None
  }
}
