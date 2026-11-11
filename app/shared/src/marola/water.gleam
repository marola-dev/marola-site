//// A beach's water quality: the agency's verdict and its sampling points.

import gleam/dynamic/decode.{type Decoder}
import gleam/option.{type Option}
import marola/band.{type Band}
import marola/decoders
import marola/i18n.{type Locale}

pub type Condition {
  Proper
  Improper
  Unclassified
  Unknown(String)
}

pub type Point {
  Point(
    point: String,
    location: String,
    lat: Float,
    lon: Float,
    condition: Condition,
    sampled_on: String,
    enterococci_per_100ml: Option(Int),
    rain: Option(String),
  )
}

pub type Water {
  Water(
    summary: String,
    unfit: Bool,
    note: Option(String),
    source: Option(String),
    points: List(Point),
  )
}

pub fn parse_condition(value: String) -> Condition {
  case value {
    "proper" -> Proper
    "improper" -> Improper
    "unknown" -> Unclassified
    other -> Unknown(other)
  }
}

/// The agency's own words are Portuguese in every language; only the
/// unclassified case goes through the catalog.
pub fn condition_label(condition: Condition, loc: Locale) -> String {
  case condition {
    Proper -> "PRÓPRIA"
    Improper -> "IMPRÓPRIA"
    Unclassified | Unknown(_) -> i18n.t(loc, "water.unclassified", [])
  }
}

/// A sampling point's marker colour; anything but proper or improper is unscored.
pub fn condition_band(condition: Condition) -> Band {
  case condition {
    Improper -> band.Avoid
    Proper -> band.Good
    _ -> band.Unscored
  }
}

/// "no data" is the one summary the board writes in words rather than the
/// agency's verdict.
pub fn has_no_data(water: Water) -> Bool {
  water.summary == "no data"
}

pub fn summary_text(water: Water, loc: Locale) -> String {
  case has_no_data(water) {
    True -> i18n.t(loc, "water.no_data", [])
    False -> water.summary
  }
}

pub fn dot_band(water: Water) -> Band {
  case water.unfit, has_no_data(water) {
    True, _ -> band.Avoid
    False, True -> band.Unscored
    False, False -> band.Good
  }
}

pub fn dot_class(water: Water) -> String {
  "wdot " <> band.css_class(dot_band(water))
}

fn point_decoder() -> Decoder(Point) {
  use point <- decode.field("point", decode.string)
  use location <- decode.field("location", decode.string)
  use lat <- decode.field("lat", decoders.number())
  use lon <- decode.field("lon", decoders.number())
  use condition <- decode.field("condition", decoders.enum(parse_condition))
  use sampled_on <- decode.field("sampled_on", decode.string)
  use enterococci_per_100ml <- decode.field(
    "enterococci_per_100ml",
    decode.optional(decode.int),
  )
  use rain <- decode.field("rain", decode.optional(decode.string))
  decode.success(Point(
    point:,
    location:,
    lat:,
    lon:,
    condition:,
    sampled_on:,
    enterococci_per_100ml:,
    rain:,
  ))
}

pub fn decoder() -> Decoder(Water) {
  use summary <- decode.field("summary", decode.string)
  use unfit <- decode.field("unfit", decode.bool)
  use note <- decode.field("note", decode.optional(decode.string))
  use source <- decode.field("source", decode.optional(decode.string))
  use points <- decode.field("points", decode.list(point_decoder()))
  decode.success(Water(summary:, unfit:, note:, source:, points:))
}
