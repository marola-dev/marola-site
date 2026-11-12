module Geo exposing (Point, compassKey, haversineKm, latLonDecoder)

import Dec
import Json.Decode as D exposing (Decoder)


type alias Point =
    { lat : Float, lon : Float }


earthRadiusKm : Float
earthRadiusKm =
    6371


radians : Float -> Float
radians degrees =
    degrees * pi / 180


{-| The great-circle distance in km, in the order of app.js `haversineKm`, so both agree to the
last digits.
-}
haversineKm : Point -> Point -> Float
haversineKm a b =
    let
        dLat =
            radians (b.lat - a.lat)

        dLon =
            radians (b.lon - a.lon)

        h =
            sin (dLat / 2)
                * sin (dLat / 2)
                + cos (radians a.lat)
                * cos (radians b.lat)
                * sin (dLon / 2)
                * sin (dLon / 2)

        -- Rounding can push h just past 1 for antipodes; asin would give NaN there.
        root =
            if h < 0 then
                0

            else
                sqrt (min h 1)
    in
    2 * earthRadiusKm * asin root


{-| The `dir.<this>` key of a bearing, to the nearest of eight points.
-}
compassKey : Float -> String
compassKey degrees =
    let
        index =
            floor (degrees / 45 + 0.5)
    in
    case modBy 8 index of
        0 ->
            "n"

        1 ->
            "ne"

        2 ->
            "e"

        3 ->
            "se"

        4 ->
            "s"

        5 ->
            "sw"

        6 ->
            "w"

        _ ->
            "nw"


{-| A `[lat, lon]` pair.
-}
latLonDecoder : Decoder Point
latLonDecoder =
    D.list Dec.number
        |> D.andThen
            (\pair ->
                case pair of
                    [ lat, lon ] ->
                        D.succeed (Point lat lon)

                    _ ->
                        D.fail "Expecting a [lat, lon] pair"
            )
