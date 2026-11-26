module Layer exposing (Layer(..), all, enabled, key, ofKey)

import Config


{-| The map layer on show. `Off` is none; the others are the buttons of the rail.
-}
type Layer
    = Off
    | Wind
    | Waves
    | Water
    | Clouds
    | Sst
    | Anomaly
    | Elnino


{-| The layers of the rail, in order.
-}
all : List Layer
all =
    [ Wind, Waves, Water, Clouds, Sst, Anomaly, Elnino ]


key : Layer -> String
key layer =
    case layer of
        Off ->
            "off"

        Wind ->
            "wind"

        Waves ->
            "waves"

        Water ->
            "water"

        Clouds ->
            "clouds"

        Sst ->
            "sst"

        Anomaly ->
            "anomaly"

        Elnino ->
            "elnino"


ofKey : String -> Maybe Layer
ofKey value =
    List.filter (\l -> key l == value) all |> List.head


enabled : Layer -> Bool
enabled layer =
    List.member (key layer) Config.enabledLayers
