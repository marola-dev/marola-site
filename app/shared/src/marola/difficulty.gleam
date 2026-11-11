//// A trail's OSM `sac_scale`. Only two values are known; the rest keep their
//// wire text so a new OSM value shows up as unrated, not as a crash.

import gleam/dynamic/decode.{type Decoder}
import gleam/option.{type Option, None, Some}
import marola/band.{type Band}

pub type Difficulty {
  Hiking
  MountainHiking
  Unrated
  Unknown(String)
}

pub fn parse(value: Option(String)) -> Difficulty {
  case value {
    Some("hiking") -> Hiking
    Some("mountain_hiking") -> MountainHiking
    Some(other) -> Unknown(other)
    None -> Unrated
  }
}

pub fn to_string(difficulty: Difficulty) -> Option(String) {
  case difficulty {
    Hiking -> Some("hiking")
    MountainHiking -> Some("mountain_hiking")
    Unknown(other) -> Some(other)
    Unrated -> None
  }
}

/// The colour band of a trail line: the same classes the score chips use.
pub fn band(difficulty: Difficulty) -> Band {
  case difficulty {
    Hiking -> band.Good
    MountainHiking -> band.Fair
    _ -> band.Unscored
  }
}

pub fn decoder() -> Decoder(Difficulty) {
  decode.optional(decode.string) |> decode.map(parse)
}
