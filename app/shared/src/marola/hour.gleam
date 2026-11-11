//// One beach hour: the best one, and every daylight hour the slider steps through.

import gleam/dynamic/decode.{type Decoder}
import gleam/option.{type Option}
import marola/decoders
import marola/level.{type Level}
import marola/note.{type Note}
import marola/wind.{type WindLevel}

pub type Best {
  Best(hour: String, score: Int, notes: List(String), note_codes: List(Note))
}

pub type Hour {
  Hour(
    h: String,
    score: Int,
    notes: List(String),
    note_codes: List(Note),
    sea_temp_c: Option(Float),
    wave_m: Option(Float),
    wind_kmh: Option(Float),
    wind_level: Option(WindLevel),
    jellyfish: Level,
    whales: Level,
  )
}

/// What a beach shows at the hour on the slider: its best hour's score and
/// notes, or an hour's. It carries no sea numbers; `beach.hour_entry` finds those.
pub type Shown {
  Shown(
    h: String,
    score: Int,
    notes: List(String),
    note_codes: List(Note),
    best: Bool,
  )
}

/// A schema-1 board has no note codes.
fn note_codes() -> Decoder(List(Note)) {
  decode.optional_field(
    "note_codes",
    [],
    decode.list(note.decoder()),
    decode.success,
  )
}

pub fn best_decoder() -> Decoder(Best) {
  use hour <- decode.field("hour", decode.string)
  use score <- decode.field("score", decode.int)
  use notes <- decode.field("notes", decode.list(decode.string))
  use note_codes <- decode.then(note_codes())
  decode.success(Best(hour:, score:, notes:, note_codes:))
}

pub fn decoder() -> Decoder(Hour) {
  use h <- decode.field("h", decode.string)
  use score <- decode.field("score", decode.int)
  use notes <- decode.field("notes", decode.list(decode.string))
  use note_codes <- decode.then(note_codes())
  use sea_temp_c <- decode.field("sea_temp_c", decoders.nullable_number())
  use wave_m <- decode.field("wave_m", decoders.nullable_number())
  use wind_kmh <- decode.field("wind_kmh", decoders.nullable_number())
  use wind_level <- decode.optional_field(
    "wind_level",
    option.None,
    decode.optional(wind.decoder()),
  )
  use jellyfish <- decode.field("jellyfish", level.decoder())
  use whales <- decode.field("whales", level.decoder())
  decode.success(Hour(
    h:,
    score:,
    notes:,
    note_codes:,
    sea_temp_c:,
    wave_m:,
    wind_kmh:,
    wind_level:,
    jellyfish:,
    whales:,
  ))
}
