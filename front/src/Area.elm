module Area exposing (Area, Bounds, Pin, decoder, listDecoder)

{-| An area of the picker: `data/areas.json` carries more, the page reads these. `bounds`, `zoom`
and `pin` are the area's own: what the camera frames, where it enters without bounds, the layer it
opens on, and the partner place it carries (the Complexo Lagunar frames its lagoons and pins Canto das Águas).
-}

import Dec exposing (required)
import Json.Decode as D exposing (Decoder)


type alias Pin =
    { name : String, lat : Float, lon : Float, url : Maybe String }


{-| West, south, east and north: the box the camera frames.
-}
type alias Bounds =
    { west : Float, south : Float, east : Float, north : Float }


type alias Area =
    { id : String
    , name : String
    , lat : Float
    , lon : Float
    , zoom : Maybe Int
    , bounds : Maybe Bounds
    , layer : Maybe String
    , pin : Maybe Pin
    }


pinDecoder : Decoder Pin
pinDecoder =
    D.succeed Pin
        |> required "name" D.string
        |> required "lat" Dec.number
        |> required "lon" Dec.number
        |> Dec.andMap (Dec.optional "url" D.string)


boundsDecoder : Decoder Bounds
boundsDecoder =
    D.list Dec.number
        |> D.andThen
            (\numbers ->
                case numbers of
                    [ west, south, east, north ] ->
                        D.succeed { west = west, south = south, east = east, north = north }

                    _ ->
                        D.fail "an area's bounds are west, south, east and north"
            )


decoder : Decoder Area
decoder =
    D.succeed Area
        |> required "id" D.string
        |> required "name" D.string
        |> required "lat" Dec.number
        |> required "lon" Dec.number
        |> Dec.andMap (Dec.optional "zoom" Dec.int)
        |> Dec.andMap (Dec.optional "bounds" boundsDecoder)
        |> Dec.andMap (Dec.optional "layer" D.string)
        |> Dec.andMap (Dec.optional "pin" pinDecoder)


{-| `{"areas": [...]}` on the site and a bare list in `site/areas.json`.
-}
listDecoder : Decoder (List Area)
listDecoder =
    D.oneOf [ D.list decoder, D.field "areas" (D.list decoder) ]
