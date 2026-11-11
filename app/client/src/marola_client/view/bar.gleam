//// The header (brand, area picker, days, near me, sound, list) and the hour
//// bar with its slider and the score legend.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute.{attribute, class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import marola/area.{type Area}
import marola/beach.{At, BestHour}
import marola/board
import marola/i18n
import marola_client/config
import marola_client/latest.{type Day}
import marola_client/model.{type Model} as mdl
import marola_client/msg.{type Msg}
import marola_client/view/text.{expanded, hidden, icon, pressed, t, ta}

fn brand(model: Model) -> Element(Msg) {
  html.div([class("brand")], [
    html.h1([], [
      icon("brand"),
      html.text("marola"),
    ]),
    html.p([class("tagline")], [html.text(t(model, "header.tagline"))]),
  ])
}

fn area_option(selected: Bool, a: Area) -> Element(Msg) {
  html.option(
    [
      attribute.value(a.id),
      attribute.title(a.name),
      attribute("aria-label", a.name),
      attribute.selected(selected),
    ],
    config.area_code(a.id, a.name),
  )
}

fn insta(model: Model) -> Element(Msg) {
  let handle = case model.area {
    Some(a) -> config.instagram(a.id)
    None -> None
  }
  let city = case model.area {
    Some(a) -> a.name
    None -> ""
  }
  case handle {
    None -> html.a([attribute.id("insta"), class("insta"), ..hidden(True)], [])
    Some("") -> {
      let soon = ta(model, "insta.soon", [i18n.arg("city", city)])
      html.a(
        [
          attribute.id("insta"),
          class("insta soon"),
          attribute("aria-disabled", "true"),
          attribute("aria-label", soon),
          attribute.title(soon),
        ],
        [icon("instagram"), html.span([], [html.text(t(model, "nav.soon"))])],
      )
    }
    Some(name) ->
      html.a(
        [
          attribute.id("insta"),
          class("insta"),
          attribute.href("https://www.instagram.com/" <> name <> "/"),
          attribute.target("_blank"),
          attribute.rel("noopener"),
          attribute(
            "aria-label",
            ta(model, "insta.label", [i18n.arg("handle", "@" <> name)]),
          ),
          attribute.title(ta(model, "insta.title", [i18n.arg("city", city)])),
        ],
        [icon("instagram"), html.span([], [html.text("@" <> name)])],
      )
  }
}

/// A third day and later are named by their date alone, so the picker fits
/// one row on a phone.
fn day_label(model: Model, index: Int, day: Day) -> List(Element(Msg)) {
  let date = html.small([], [html.text(string.drop_start(day.day, 5))])
  case index {
    0 -> [html.text(t(model, "day.today") <> " "), date]
    1 -> [html.text(t(model, "day.tomorrow") <> " "), date]
    _ -> [html.text(string.drop_start(day.day, 5))]
  }
}

fn days(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.id("days"),
      class("segmented"),
      attribute("role", "group"),
      attribute("aria-label", t(model, "controls.day")),
    ],
    list.index_map(model.days, fn(day, i) {
      html.button(
        [
          attribute.type_("button"),
          attribute("data-day", day.day),
          event.on_click(msg.DayPicked(day.day)),
          ..case model.day == Some(day.day) {
            True -> [class("on")]
            False -> []
          }
        ],
        day_label(model, i, day),
      )
    }),
  )
}

fn control(
  model: Model,
  id: String,
  icon_name: String,
  label: String,
  title: String,
  extra: List(attribute.Attribute(Msg)),
  message: Msg,
) -> Element(Msg) {
  html.button(
    [
      attribute.id(id),
      attribute.type_("button"),
      attribute.title(case title {
        "" -> label
        _ -> t(model, title)
      }),
      event.on_click(message),
      ..extra
    ],
    [icon(icon_name), html.span([], [html.text(label)])],
  )
}

pub fn header(model: Model) -> Element(Msg) {
  let picked = case model.area {
    Some(a) -> a.id
    None -> ""
  }
  html.header([class("bar")], [
    brand(model),
    html.div([class("controls")], [
      html.select(
        [
          attribute.id("area"),
          attribute("aria-label", t(model, "controls.area")),
          event.on_change(msg.AreaPicked),
        ],
        list.map(model.areas, fn(a) { area_option(a.id == picked, a) }),
      ),
      insta(model),
      days(model),
      control(
        model,
        "near",
        "locate",
        t(model, "controls.near"),
        "controls.near_title",
        [pressed(option.is_some(model.here))],
        msg.NearPressed,
      ),
      control(
        model,
        "sound",
        "sound",
        t(model, "controls.sound"),
        "controls.sound_title",
        [pressed(model.sound_on)],
        msg.SoundPressed,
      ),
      control(
        model,
        "toggle-list",
        "list",
        t(model, "controls.list"),
        "",
        [
          attribute("aria-controls", "list"),
          expanded(model.panel == mdl.BeachList),
        ],
        msg.ListToggled,
      ),
    ]),
  ])
}

/// The slider's index: -1 is each beach at its own best hour.
pub fn hour_index(model: Model) -> Int {
  case model.selection {
    BestHour -> -1
    At(h) ->
      list.index_map(model.hours, fn(x, i) { #(x, i) })
      |> list.find(fn(pair) { pair.0 == h })
      |> option.from_result
      |> option.map(fn(pair) { pair.1 })
      |> option.unwrap(-1)
  }
}

pub fn hour_label(model: Model) -> String {
  case model.selection, model.board {
    At(h), Some(b) ->
      ta(model, "hour.at", [
        i18n.arg("h", h),
        i18n.arg("past", case board.is_past(b, h) {
          True -> "yes"
          False -> "no"
        }),
      ])
    _, _ -> t(model, "hour.best")
  }
}

fn chip(band: String, label: List(Element(Msg))) -> Element(Msg) {
  html.span([], [html.i([class(band)], []), ..label])
}

fn legend(model: Model) -> Element(Msg) {
  html.span([class("legend"), attribute("aria-hidden", "true")], [
    html.b([], [html.text(t(model, "legend.score"))]),
    html.text(" "),
    chip("c70", [html.text("≥70")]),
    chip("c40", [html.text("40–69")]),
    chip("c1", [html.text("1–39")]),
    chip("c0", [html.span([], [html.text(t(model, "legend.unfit"))])]),
    chip("cna", [html.span([], [html.text(t(model, "legend.no_data"))])]),
    html.span([class("wave-key")], [
      html.span([], [html.text(t(model, "legend.wave_key"))]),
    ]),
  ])
}

pub fn hourbar(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.id("hourbar"),
      class("hourbar"),
      ..hidden(list.is_empty(model.hours))
    ],
    [
      html.label([attribute.for("hour")], [
        html.span([attribute.id("hour-label")], [
          html.text(hour_label(model)),
        ]),
      ]),
      html.input([
        attribute.id("hour"),
        attribute.type_("range"),
        attribute.min("-1"),
        attribute.max(int.to_string(list.length(model.hours) - 1)),
        attribute.step("1"),
        attribute.value(int.to_string(hour_index(model))),
        attribute("aria-label", t(model, "hour.slider")),
        event.on_input(fn(value) {
          msg.HourMoved(
            int.parse(value) |> option.from_result |> option.unwrap(-1),
          )
        }),
      ]),
      legend(model),
    ],
  )
}
