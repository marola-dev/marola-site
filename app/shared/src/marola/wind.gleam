//// The wind band an hour carries. A board from before MIP-0054 has none.

import gleam/dynamic/decode.{type Decoder}
import marola/decoders

pub type WindLevel {
  Calm
  Breezy
  Strong
  Unknown(String)
}

pub fn parse(value: String) -> WindLevel {
  case value {
    "calm" -> Calm
    "breezy" -> Breezy
    "strong" -> Strong
    other -> Unknown(other)
  }
}

pub fn to_string(level: WindLevel) -> String {
  case level {
    Calm -> "calm"
    Breezy -> "breezy"
    Strong -> "strong"
    Unknown(other) -> other
  }
}

pub fn decoder() -> Decoder(WindLevel) {
  decoders.enum(parse)
}
