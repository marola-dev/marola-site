//// A board file, or the news that it is newer than this page.

import gleam/dynamic/decode.{type Decoder}
import gleam/list
import marola/board.{type Board}

pub type Loaded {
  Read(Board)
  /// The schema number the file carries; this page reads `board.schemas`.
  Newer(schema: Int)
}

pub fn decoder() -> Decoder(Loaded) {
  use schema <- decode.field("schema", decode.int)
  case list.contains(board.schemas, schema) {
    True -> board.decoder() |> decode.map(Read)
    False -> decode.success(Newer(schema))
  }
}
