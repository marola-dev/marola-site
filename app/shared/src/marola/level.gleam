//// The Low / Moderate / High likelihood of jellyfish and whales.

import gleam/dynamic/decode.{type Decoder}
import marola/decoders

pub type Level {
  Low
  Moderate
  High
  Unknown(String)
}

pub fn parse(value: String) -> Level {
  case value {
    "Low" -> Low
    "Moderate" -> Moderate
    "High" -> High
    other -> Unknown(other)
  }
}

pub fn to_string(level: Level) -> String {
  case level {
    Low -> "Low"
    Moderate -> "Moderate"
    High -> "High"
    Unknown(other) -> other
  }
}

pub fn decoder() -> Decoder(Level) {
  decoders.enum(parse)
}
