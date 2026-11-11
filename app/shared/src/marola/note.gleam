//// The reason codes of a score (MIP-0054 section 5.1). The page words each
//// code per language; a code it does not know keeps the board's English.

import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import marola/decoders

pub type Code {
  RoughSeas
  Choppy
  NoWaveData
  StrongWind
  Breezy
  NoWindData
  ColdWater
  WarmWater
  NoSeaTempData
  RainLikely
  Dark
  JellyfishElevated
  JellyfishSome
  WaterStale
  WaterUnfit
  WaterMixed
  Unknown(String)
}

/// The args of a code: numbers stay numbers, `avoid` is a list of places.
pub type Arg {
  Number(Float)
  Text(String)
  Places(List(String))
  Other
}

pub type Note {
  Note(code: Code, args: Dict(String, Arg))
}

pub fn parse_code(value: String) -> Code {
  case value {
    "rough_seas" -> RoughSeas
    "choppy" -> Choppy
    "no_wave_data" -> NoWaveData
    "strong_wind" -> StrongWind
    "breezy" -> Breezy
    "no_wind_data" -> NoWindData
    "cold_water" -> ColdWater
    "warm_water" -> WarmWater
    "no_sea_temp_data" -> NoSeaTempData
    "rain_likely" -> RainLikely
    "dark" -> Dark
    "jellyfish_elevated" -> JellyfishElevated
    "jellyfish_some" -> JellyfishSome
    "water_stale" -> WaterStale
    "water_unfit" -> WaterUnfit
    "water_mixed" -> WaterMixed
    other -> Unknown(other)
  }
}

pub fn code_to_string(code: Code) -> String {
  case code {
    RoughSeas -> "rough_seas"
    Choppy -> "choppy"
    NoWaveData -> "no_wave_data"
    StrongWind -> "strong_wind"
    Breezy -> "breezy"
    NoWindData -> "no_wind_data"
    ColdWater -> "cold_water"
    WarmWater -> "warm_water"
    NoSeaTempData -> "no_sea_temp_data"
    RainLikely -> "rain_likely"
    Dark -> "dark"
    JellyfishElevated -> "jellyfish_elevated"
    JellyfishSome -> "jellyfish_some"
    WaterStale -> "water_stale"
    WaterUnfit -> "water_unfit"
    WaterMixed -> "water_mixed"
    Unknown(other) -> other
  }
}

fn arg_decoder() -> Decoder(Arg) {
  decode.one_of(decoders.number() |> decode.map(Number), [
    decode.string |> decode.map(Text),
    decode.list(decode.string) |> decode.map(Places),
    decode.success(Other),
  ])
}

pub fn decoder() -> Decoder(Note) {
  use code <- decode.field("code", decoders.enum(parse_code))
  use args <- decode.field("args", decode.dict(decode.string, arg_decoder()))
  decode.success(Note(code:, args:))
}
