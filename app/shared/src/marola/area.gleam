//// An area of the picker. `data/areas.json` carries more per area; the page
//// reads the id, the name and the centre the map opens on.

import gleam/dynamic/decode.{type Decoder}
import marola/decoders

pub type Area {
  Area(id: String, name: String, lat: Float, lon: Float)
}

pub fn decoder() -> Decoder(Area) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use lat <- decode.field("lat", decoders.number())
  use lon <- decode.field("lon", decoders.number())
  decode.success(Area(id:, name:, lat:, lon:))
}

/// The file is `{"areas": [...]}` on the site and a bare list in `site/areas.json`.
pub fn list_decoder() -> Decoder(List(Area)) {
  decode.one_of(decode.list(decoder()), [
    decode.field("areas", decode.list(decoder()), decode.success),
  ])
}
