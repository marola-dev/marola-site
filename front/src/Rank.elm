module Rank exposing (byDistance, byScore)

{-| The list's two orders; the distance travels beside the beach. -}

import Beach exposing (Beach, Selection)
import Geo exposing (Point)


{-| Nearest first, each with its distance in km. `List.sortBy` is stable, so ties keep the board's order.
-}
byDistance : List Beach -> Point -> List ( Beach, Float )
byDistance beaches here =
    beaches
        |> List.map (\b -> ( b, Geo.haversineKm here { lat = b.lat, lon = b.lon } ))
        |> List.sortBy Tuple.second


{-| Best score first at the hour on show; a beach dark then goes last.
-}
byScore : List Beach -> Selection -> List Beach
byScore beaches selection =
    let
        score b =
            Beach.shown b selection |> Maybe.map .score |> Maybe.withDefault -1
    in
    List.sortBy (\b -> negate (score b)) beaches
