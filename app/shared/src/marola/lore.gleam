//// The day's sea-lore paragraph and the source it is quoted from.

import gleam/dynamic/decode.{type Decoder}
import marola/decoders

pub type Kind {
  Secret
  Creature
  Unknown(String)
}

pub type Lore {
  Lore(kind: Kind, text: String, source: String, lang: String)
}

pub fn parse_kind(value: String) -> Kind {
  case value {
    "secret" -> Secret
    "creature" -> Creature
    other -> Unknown(other)
  }
}

/// The footer's toggle label: only a creature has its own; every other kind
/// reads as a fact.
pub fn label_key(kind: Kind) -> String {
  case kind {
    Creature -> "lore.creature"
    _ -> "lore.fact"
  }
}

pub fn decoder() -> Decoder(Lore) {
  use kind <- decode.field("kind", decoders.enum(parse_kind))
  use text <- decode.field("text", decode.string)
  use source <- decode.field("source", decode.string)
  use lang <- decode.field("lang", decode.string)
  decode.success(Lore(kind:, text:, source:, lang:))
}
