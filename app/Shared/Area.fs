namespace Marola

open Thoth.Json.Core

/// An area of the picker. `data/areas.json` carries more per area; the page reads the id, the
/// name and the centre the map opens on.
type Area =
    { Id: string
      Name: string
      Lat: float
      Lon: float }

module Area =

    let decoder: Decoder<Area> =
        Decode.object (fun get ->
            { Id = get.Required.Field "id" Decode.string
              Name = get.Required.Field "name" Decode.string
              Lat = get.Required.Field "lat" Decoders.number
              Lon = get.Required.Field "lon" Decoders.number })

    /// The file is `{"areas": [...]}` on the site and a bare list in `site/areas.json`.
    let listDecoder: Decoder<Area list> =
        Decode.oneOf [ Decode.list decoder; Decode.field "areas" (Decode.list decoder) ]
