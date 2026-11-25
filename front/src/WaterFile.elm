module WaterFile exposing (WaterFile, decoder, spot)

{-| An area's own sampling points, from `data/water/<area>.json`: the official points the board
never draws because the app matches them to a beach by name and an inland name (`lagoa …`,
`canal …`) never falls back to distance (`docs/4-reference.md`). The file is a copy of the
agency's bulletin, with its sampling day, not live data.
-}

import Dec exposing (required)
import Json.Decode as D exposing (Decoder)
import Water exposing (WaterPoint)


type alias WaterFile =
    { area : String
    , source : String
    , sampledOn : String
    , note : Maybe String
    , points : List WaterPoint
    }


decoder : Decoder WaterFile
decoder =
    D.succeed WaterFile
        |> required "area" D.string
        |> required "source" D.string
        |> required "sampled_on" D.string
        |> required "note" (Dec.nullable D.string)
        |> required "points" (D.list Water.pointDecoder)


{-| A point's place, at about a metre: the same sample drawn once, whether it came from the board
or from this file.
-}
spot : WaterPoint -> ( Int, Int )
spot p =
    ( round (p.lat * 100000), round (p.lon * 100000) )
