module Area exposing (Area, Bounds, Pin, decoder, isDive, isPeak, isWomen, listDecoder, pinDescription, pinLabel)

{-| An area of the picker: `data/areas.json` carries more, the page reads these. `bounds`, `zoom`
and `pin` are the area's own: what the camera frames, where it enters without bounds, the layer it
opens on, and the named places it carries (the Complexo Lagunar frames its lagoons and pins the
Instituto Canto das Águas; Paraná pins the Ilha do Mel; Minas Gerais pins Wberdiver, the source
of the São Francisco and its four starting regions; Florianópolis pins three islands and Casa Örüm).
-}

import Dec exposing (required)
import Dict exposing (Dict)
import I18n exposing (Locale)
import Json.Decode as D exposing (Decoder)
import Language


type alias Pin =
    { name : String
    , names : Dict String String
    , descriptions : Dict String String
    , kind : String
    , lat : Float
    , lon : Float
    , url : Maybe String
    , labelBelow : Bool
    }


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
    , pins : List Pin
    }


pinDecoder : Decoder Pin
pinDecoder =
    D.succeed Pin
        |> required "name" D.string
        |> Dec.andMap (Dec.optional "names" (D.dict D.string) |> D.map (Maybe.withDefault Dict.empty))
        |> Dec.andMap (Dec.optional "descriptions" (D.dict D.string) |> D.map (Maybe.withDefault Dict.empty))
        |> Dec.andMap (Dec.optional "kind" D.string |> D.map (Maybe.withDefault "place"))
        |> required "lat" Dec.number
        |> required "lon" Dec.number
        |> Dec.andMap (Dec.optional "url" D.string)
        |> Dec.andMap (Dec.optional "label_below" D.bool |> D.map (Maybe.withDefault False))


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
        |> Dec.andMap (Dec.optional "pins" (D.list pinDecoder) |> D.map (Maybe.withDefault []))


{-| `{"areas": [...]}` on the site and a bare list in `site/areas.json`.
-}
listDecoder : Decoder (List Area)
listDecoder =
    D.oneOf [ D.list decoder, D.field "areas" (D.list decoder) ]


{-| The pin's name in the page language, falling back to its Portuguese name when the area names
no translation.
-}
pinLabel : Locale -> Pin -> String
pinLabel loc pin =
    Dict.get (Language.tag loc.language) pin.names
        |> Maybe.withDefault pin.name


{-| The pin's one-line description in the page language, when the area carries one.
-}
pinDescription : Locale -> Pin -> Maybe String
pinDescription loc pin =
    Dict.get (Language.tag loc.language) pin.descriptions


{-| A diving site: the pin belongs to the scuba layer, not to the plain map.
-}
isDive : Pin -> Bool
isDive pin =
    pin.kind == "dive"


{-| A peak: a place pin with a mountain marker and no permanent label, so the three highest
points of a state do not stack their names on top of each other at a wide zoom.
-}
isPeak : Pin -> Bool
isPeak pin =
    pin.kind == "peak"


{-| A women's place: a round marker with the Venus symbol.
-}
isWomen : Pin -> Bool
isWomen pin =
    pin.kind == "women"
