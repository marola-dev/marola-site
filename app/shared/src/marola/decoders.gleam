//// Decoder helpers shared by the board types.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/option.{type Option}

/// A JSON number. Erlang keeps `3` and `3.0` apart; JavaScript does not.
pub fn number() -> Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

pub fn nullable_number() -> Decoder(Option(Float)) {
  decode.optional(number())
}

/// A closed set that must never crash the page: a value outside it becomes
/// the caller's `Unknown(String)` variant instead of a decode error.
pub fn enum(parse: fn(String) -> a) -> Decoder(a) {
  decode.string |> decode.map(parse)
}
