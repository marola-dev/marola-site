//// The card of the picked beach. Touch has no hover, so it opens with the
//// tooltip's aspect row (MIP-0009 section 3).

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute.{attribute, class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import marola/aspects
import marola/band
import marola/beach.{type Beach, type Tide}
import marola/board
import marola/fmt
import marola/hour.{type Shown}
import marola/i18n
import marola/level
import marola/notes
import marola/water
import marola_client/aspects_view
import marola_client/dom
import marola_client/model.{type Model}
import marola_client/msg.{type Msg}
import marola_client/view/text.{hidden, t, ta, with_slot}

fn yes(on: Bool) -> String {
  case on {
    True -> "yes"
    False -> "no"
  }
}

/// Coordinates keep the dot in every language: a decimal comma would collide
/// with the separator.
pub fn fixed4(n: Float) -> String {
  let scaled = float.round(float.absolute_value(n) *. 10_000.0)
  let whole = scaled / 10_000
  let frac = int.to_string(scaled % 10_000) |> string.pad_start(4, "0")
  let sign = case n <. 0.0 && scaled != 0 {
    True -> "-"
    False -> ""
  }
  sign <> int.to_string(whole) <> "." <> frac
}

fn headline(model: Model, b: Beach, shown: Option(Shown)) -> Element(Msg) {
  case shown {
    None -> html.p([class("headline past")], [html.text(t(model, "tip.dark"))])
    Some(s) -> {
      let past = case model.board {
        Some(board) -> board.is_past(board, s.h)
        None -> False
      }
      let at = html.b([], [html.text(s.h)])
      let words = case s.best {
        True -> with_slot(model, "card.best_at", [], "h", [at])
        False ->
          with_slot(
            model,
            "card.at_best",
            [
              i18n.arg("best", b.best.hour),
              i18n.arg("score", int.to_string(b.best.score)),
            ],
            "h",
            [at],
          )
      }
      html.p([class("headline")], [
        html.span(
          [
            class(
              "score "
              <> band.css_class(band.of_score(Some(s.score), b.water.unfit)),
            ),
          ],
          [html.text(int.to_string(s.score) <> "/100")],
        ),
        html.text(" "),
        ..list.append(words, case past {
          True -> [
            html.text(" "),
            html.span([class("past")], [html.text(t(model, "card.past"))]),
          ]
          False -> []
        })
      ])
    }
  }
}

fn why(model: Model, shown: Option(Shown)) -> Element(Msg) {
  case option.map(shown, notes.of(_, model.loc)) {
    Some([_, ..] as lines) ->
      html.ul([], list.map(lines, fn(n) { html.li([], [html.text(n)]) }))
    _ -> html.text(t(model, "card.good"))
  }
}

fn condition_class(condition: water.Condition) -> String {
  case condition {
    water.Improper -> "water improper"
    water.Proper -> "water proper"
    _ -> "water"
  }
}

fn point_item(model: Model, p: water.Point) -> Element(Msg) {
  let count = case p.enterococci_per_100ml {
    Some(n) -> [
      html.text(
        ", " <> ta(model, "card.enterococci", [i18n.arg("n", int.to_string(n))]),
      ),
    ]
    None -> []
  }
  html.li([], [
    html.span([class(condition_class(p.condition))], [
      html.text(
        p.point
        <> " ("
        <> p.location
        <> "): "
        <> water.condition_label(p.condition, model.loc),
      ),
    ]),
    html.text(", " <> p.sampled_on),
    ..count
  ])
}

fn water_cell(model: Model, b: Beach) -> List(Element(Msg)) {
  let summary = water.summary_text(b.water, model.loc)
  let points = case b.water.points {
    [] -> []
    points -> [html.ul([], list.map(points, point_item(model, _)))]
  }
  let source = case b.water.source {
    Some(s) -> [
      html.small(
        [],
        with_slot(model, "card.source", [], "source", [
          html.span([class("src")], [html.text(s)]),
        ]),
      ),
    ]
    None -> []
  }
  list.flatten([
    [
      html.span(
        [
          class(case b.water.unfit {
            True -> "unfit"
            False -> "water"
          }),
        ],
        [html.text(summary)],
      ),
    ],
    points,
    source,
  ])
}

fn tide_text(model: Model, tide: Tide) -> String {
  ta(
    model,
    case tide.high {
      True -> "tide.high"
      False -> "tide.low"
    },
    [
      i18n.arg("time", tide.time),
      i18n.arg("m", fmt.signed(model.loc, tide.m, 1)),
    ],
  )
}

fn tides_cell(model: Model, b: Beach) -> List(Element(Msg)) {
  case b.tides {
    [] -> [html.text(t(model, "tide.none"))]
    tides -> [
      html.text(string.join(list.map(tides, tide_text(model, _)), ", ") <> " "),
      html.small([], [html.text(t(model, "tide.hourly"))]),
    ]
  }
}

fn sea_text(model: Model, b: Beach) -> String {
  let sea = b.sea
  let loc = model.loc
  let extra = fn(value: Option(Float), key: String, unit: String) {
    case value {
      Some(_) -> [
        ta(model, key, [i18n.arg("v", fmt.value(loc, value, unit, 1))]),
      ]
      None -> []
    }
  }
  list.flatten([
    [
      fmt.value(loc, sea.temp_c, "°C", 1),
      fmt.waves(loc, sea.wave_m, sea.period_s),
    ],
    extra(sea.swell_m, "card.swell", " m"),
    extra(sea.current_kmh, "card.current", " km/h"),
  ])
  |> string.join(", ")
}

fn air_text(model: Model, b: Beach) -> String {
  let sea = b.sea
  let loc = model.loc
  list.flatten([
    [
      fmt.value(loc, sea.air_temp_c, "°C", 0),
      ta(model, "cell.wind", [
        i18n.arg("v", fmt.value(loc, sea.wind_kmh, " km/h", 0)),
      ]),
    ],
    case sea.uv {
      Some(_) -> [
        ta(model, "card.uv", [i18n.arg("v", fmt.value(loc, sea.uv, "", 0))]),
      ]
      None -> []
    },
    case sea.rain_pct {
      Some(pct) -> [
        ta(model, "card.rain", [i18n.arg("pct", fmt.num(loc, pct, 0))]),
      ]
      None -> []
    },
  ])
  |> string.join(", ")
}

fn whales_text(model: Model, b: Beach) -> String {
  ta(model, "card.whales_now", [
    i18n.arg(
      "level",
      i18n.word(model.loc, "lvl.", level.to_string(b.whales.now)),
    ),
    i18n.arg("best", yes(option.is_some(b.whales.peak))),
    i18n.arg("peak", option.unwrap(b.whales.peak, "")),
    i18n.arg("season", yes(b.whales.season)),
  ])
}

fn where_cell(b: Beach) -> Element(Msg) {
  let lat = float.to_string(b.lat)
  let lon = float.to_string(b.lon)
  html.a(
    [
      attribute.href(
        "https://www.openstreetmap.org/?mlat="
        <> lat
        <> "&mlon="
        <> lon
        <> "#map=15/"
        <> lat
        <> "/"
        <> lon,
      ),
      attribute.target("_blank"),
      attribute.rel("noopener"),
    ],
    [html.text(fixed4(b.lat) <> ", " <> fixed4(b.lon))],
  )
}

fn row(
  model: Model,
  key: String,
  body: List(Element(Msg)),
) -> List(Element(Msg)) {
  [html.dt([], [html.text(t(model, key))]), html.dd([], body)]
}

fn body(model: Model, b: Beach) -> Element(Msg) {
  let shown = beach.shown(b, model.selection)
  let tip = aspects.of(b, shown, model.loc)
  html.section(
    [attribute.id("card"), class("card"), attribute("aria-live", "polite")],
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
      html.h2([], [html.text(b.name)]),
      html.div(
        [class("aspects")],
        list.map(aspects_view.children(tip), dom.to_lustre),
      ),
      headline(model, b, shown),
      html.dl(
        [],
        list.flatten([
          row(model, "card.why", [why(model, shown)]),
          row(model, "card.water", water_cell(model, b)),
          row(model, "card.sea", [
            html.text(sea_text(model, b) <> " "),
            html.small([], [
              html.text(ta(model, "card.at", [i18n.arg("h", b.best.hour)])),
            ]),
          ]),
          row(model, "card.tide", tides_cell(model, b)),
          row(model, "card.air", [html.text(air_text(model, b))]),
          row(model, "card.jellyfish", [
            html.text(i18n.word(model.loc, "lvl.", level.to_string(b.jellyfish))),
          ]),
          row(model, "card.whales", [html.text(whales_text(model, b))]),
          row(model, "card.where", [where_cell(b)]),
        ]),
      ),
    ],
  )
}

pub fn view(model: Model) -> Element(Msg) {
  let picked = case model.selected, model.board {
    Some(name), Some(board) ->
      list.find(board.beaches, fn(b) { b.name == name }) |> option.from_result
    _, _ -> None
  }
  case picked {
    Some(b) -> body(model, b)
    None ->
      html.section([attribute.id("card"), class("card"), ..hidden(True)], [])
  }
}
