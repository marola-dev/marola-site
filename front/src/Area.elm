module Area exposing (Area, decoder, listDecoder)

import Dec
import Json.Decode as D exposing (Decoder)


{-| An area of the picker: `data/areas.json` carries more, the page reads these.
-}
type alias Area =
    { id : String, name : String, lat : Float, lon : Float }


decoder : Decoder Area
decoder =
    D.map4 Area (D.field "id" D.string) (D.field "name" D.string) (D.field "lat" Dec.number) (D.field "lon" Dec.number)


{-| `{"areas": [...]}` on the site and a bare list in `site/areas.json`.
-}
listDecoder : Decoder (List Area)
listDecoder =
    D.oneOf [ D.list decoder, D.field "areas" (D.list decoder) ]
