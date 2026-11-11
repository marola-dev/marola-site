//// One area, one day: every nearby beach with every daylight hour scored
//// (MIP-0005 section 5.2). The decoder follows `site/board.schema.json`.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import gleam/order
import gleam/string
import marola/beach.{type Beach}
import marola/lore.{type Lore}
import marola/trail.{type Trail}

/// The schemas this page reads; 2 adds note codes. A later one is a board
/// newer than the page.
pub const schemas = [1, 2]

pub type Sources {
  Sources(beaches: String, forecast: String, water: Option(String))
}

pub type Board {
  Board(
    schema: Int,
    area: String,
    day: String,
    today: String,
    generated_at: String,
    sources: Sources,
    lore: Option(Lore),
    beaches: List(Beach),
    trails: List(Trail),
  )
}

fn sources_decoder() -> Decoder(Sources) {
  use beaches <- decode.field("beaches", decode.string)
  use forecast <- decode.field("forecast", decode.string)
  use water <- decode.field("water", decode.optional(decode.string))
  decode.success(Sources(beaches:, forecast:, water:))
}

pub fn decoder() -> Decoder(Board) {
  use schema <- decode.field("schema", decode.int)
  case list.contains(schemas, schema) {
    False -> decode.failure(empty(schema), "schema " <> schemas_text())
    True -> body(schema)
  }
}

fn body(schema: Int) -> Decoder(Board) {
  use area <- decode.field("area", decode.string)
  use day <- decode.field("day", decode.string)
  use today <- decode.field("today", decode.string)
  use generated_at <- decode.field("generated_at", decode.string)
  use sources <- decode.field("sources", sources_decoder())
  use lore <- decode.field("lore", decode.optional(lore.decoder()))
  use beaches <- decode.field("beaches", decode.list(beach.decoder()))
  use trails <- decode.optional_field(
    "trails",
    [],
    decode.list(trail.decoder()),
  )
  decode.success(Board(
    schema:,
    area:,
    day:,
    today:,
    generated_at:,
    sources:,
    lore:,
    beaches:,
    trails:,
  ))
}

fn schemas_text() -> String {
  list.map(schemas, int.to_string) |> string.join(" or ")
}

/// The placeholder `decode.failure` needs; it is never returned as a value.
fn empty(schema: Int) -> Board {
  Board(
    schema:,
    area: "",
    day: "",
    today: "",
    generated_at: "",
    sources: Sources("", "", None),
    lore: None,
    beaches: [],
    trails: [],
  )
}

/// The union of the beaches' hours, sorted: the slider's stops.
pub fn hours(board: Board) -> List(String) {
  board.beaches
  |> list.flat_map(fn(b) { list.map(b.hours, fn(h) { h.h }) })
  |> list.unique
  |> list.sort(string.compare)
}

/// Whether `h` has passed: only on the day the board was made, and only
/// against the generation time.
pub fn is_past(board: Board, h: String) -> Bool {
  case board.day == board.today {
    False -> False
    True ->
      string.compare(h, string.slice(board.generated_at, 11, 5)) == order.Lt
  }
}
