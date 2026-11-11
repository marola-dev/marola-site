//// An area of the picker. `data/areas.json` carries more per area; the page
//// reads only the id and the name.

import gleam/dynamic/decode.{type Decoder}

pub type Area {
  Area(id: String, name: String)
}

pub fn decoder() -> Decoder(Area) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  decode.success(Area(id:, name:))
}

/// The file is `{"areas": [...]}` on the site and a bare list in `site/areas.json`.
pub fn list_decoder() -> Decoder(List(Area)) {
  decode.one_of(decode.list(decoder()), [
    decode.field("areas", decode.list(decoder()), decode.success),
  ])
}
