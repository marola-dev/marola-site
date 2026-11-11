//// Words for the view: a catalog message, plain or with a piece of markup in
//// the middle. The markup is never part of a message: the piece is a Lustre
//// element put where a marker stood, so a message cannot inject any.

import gleam/dynamic/decode
import gleam/list
import gleam/string
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/event
import marola/i18n
import marola/icu
import marola_client/dom
import marola_client/icons
import marola_client/model.{type Model}

pub fn t(model: Model, key: String) -> String {
  i18n.t(model.loc, key, [])
}

pub fn ta(model: Model, key: String, args: List(#(String, icu.Arg))) -> String {
  i18n.t(model.loc, key, args)
}

/// A private-use character no catalog message contains.
const marker = "\u{E000}"

/// The message with `slot` where the argument `name` is. A message that does
/// not use the argument (a branch of a `select`) comes back as text alone.
pub fn with_slot(
  model: Model,
  key: String,
  args: List(#(String, icu.Arg)),
  name: String,
  slot: List(Element(msg)),
) -> List(Element(msg)) {
  let text = i18n.t(model.loc, key, [i18n.arg(name, marker), ..args])
  string.split(text, marker)
  |> list.index_map(fn(part, i) {
    case i {
      0 -> [element.text(part)]
      _ -> list.append(slot, [element.text(part)])
    }
  })
  |> list.flatten
}

/// The `hidden` attribute when `on`, else nothing.
pub fn hidden(on: Bool) -> List(Attribute(msg)) {
  case on {
    True -> [attribute.attribute("hidden", "")]
    False -> []
  }
}

pub fn pressed(on: Bool) -> Attribute(msg) {
  attribute.attribute("aria-pressed", case on {
    True -> "true"
    False -> "false"
  })
}

pub fn expanded(on: Bool) -> Attribute(msg) {
  attribute.attribute("aria-expanded", case on {
    True -> "true"
    False -> "false"
  })
}

/// A line icon as a Lustre element.
pub fn icon(name: String) -> Element(msg) {
  dom.to_lustre(icons.icon(name))
}

/// Enter or Space on a focused element does what a click does; any other
/// key fails to decode, so it dispatches nothing.
pub fn on_activate(message: msg) -> Attribute(msg) {
  event.on("keydown", {
    use key <- decode.field("key", decode.string)
    case key {
      "Enter" | " " -> decode.success(message)
      _ -> decode.failure(message, "key")
    }
  })
}
