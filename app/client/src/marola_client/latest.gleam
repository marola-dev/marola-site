//// `data/<area>/latest.json`: the days that have a board, and each one's file.

import gleam/dynamic/decode.{type Decoder}

pub type Day {
  Day(day: String, file: String)
}

pub fn decoder() -> Decoder(List(Day)) {
  decode.field("days", decode.list(day_decoder()), decode.success)
}

fn day_decoder() -> Decoder(Day) {
  use day <- decode.field("day", decode.string)
  use file <- decode.field("file", decode.string)
  decode.success(Day(day:, file:))
}
