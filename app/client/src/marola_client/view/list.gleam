//// The ranked list of beaches: best score first, or nearest first once the
//// visitor shares where they are.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{attribute, class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import marola/band
import marola/beach.{type Beach}
import marola/fmt
import marola/rank
import marola/water
import marola_client/model.{type Model} as mdl
import marola_client/msg.{type Msg}
import marola_client/view/text.{hidden, t}

/// Each beach with its distance when the visitor shared a position.
pub fn ranked(model: Model) -> List(#(Beach, Option(Float))) {
  let beaches = case model.board {
    Some(board) -> board.beaches
    None -> []
  }
  case model.here {
    Some(here) ->
      rank.by_distance(beaches, here)
      |> list.map(fn(pair) { #(pair.0, Some(pair.1)) })
    None ->
      rank.by_score(beaches, model.selection)
      |> list.map(fn(b) { #(b, None) })
  }
}

fn row(model: Model, entry: #(Beach, Option(Float))) -> Element(Msg) {
  let #(b, km) = entry
  let shown = beach.shown(b, model.selection)
  let score = option.map(shown, fn(s) { s.score })
  let chip = case score {
    Some(s) -> int.to_string(s)
    None -> "–"
  }
  let hour = case shown {
    Some(s) -> s.h
    None -> t(model, "list.dark")
  }
  let summary = water.summary_text(b.water, model.loc)
  let water_span = case b.water.unfit, b.water.points {
    True, _ -> [
      html.text(" "),
      html.span([class("water unfit")], [html.text(summary)]),
    ]
    False, [_, ..] -> [
      html.text(" "),
      html.span([class("water")], [html.text(summary)]),
    ]
    False, [] -> []
  }
  let distance = case km {
    Some(d) -> [
      html.text(" "),
      html.span([class("dist")], [html.text(fmt.num(model.loc, d, 1) <> " km")]),
    ]
    None -> []
  }
  html.li(
    [
      attribute("data-name", b.name),
      attribute("tabindex", "0"),
      attribute("role", "button"),
      event.on_click(msg.BeachPicked(b.name, True)),
      text.on_activate(msg.BeachPicked(b.name, True)),
    ],
    list.flatten([
      [
        html.span(
          [
            class(
              "score " <> band.css_class(band.of_score(score, b.water.unfit)),
            ),
          ],
          [html.text(chip)],
        ),
        html.text(b.name <> " "),
        html.span([class("dist")], [html.text(hour)]),
      ],
      distance,
      water_span,
    ]),
  )
}

pub fn view(model: Model) -> Element(Msg) {
  html.aside(
    [
      attribute.id("list"),
      class("list"),
      ..hidden(model.panel != mdl.BeachList)
    ],
    [html.ol([], list.map(ranked(model), row(model, _)))],
  )
}
