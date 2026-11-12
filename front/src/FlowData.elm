module FlowData exposing (json)

{-| The flow layer's data: the wind or wave field between the beaches at the slider's hour, as
the flat arrays `flow_layer_ffi.mjs` samples every frame.
-}

import Array
import Beach
import Config
import Flow exposing (Cell, Reading)
import Json.Encode as E
import Layer exposing (Layer)
import Model exposing (Model)


{-| The top of the colour ramp: km/h of wind, metres of wave.
-}
maxOf : Layer -> Float
maxOf layer =
    case layer of
        Layer.Wind ->
            40

        _ ->
            3


readings : Model -> Layer -> List Reading
readings model layer =
    Model.beaches model
        |> List.filterMap
            (\b ->
                -- The directions are the board's, taken at the best hour.
                Beach.hourEntry b (Beach.shown b model.selection)
                    |> Maybe.map
                        (\entry ->
                            case layer of
                                Layer.Wind ->
                                    { lon = b.lon, lat = b.lat, mag = entry.windKmh, dir = b.sea.windDirDeg }

                                _ ->
                                    { lon = b.lon, lat = b.lat, mag = entry.waveM, dir = b.sea.waveDirDeg }
                        )
            )


{-| `v` rounded to 4 decimals, half to even.
-}
round4 : Float -> Float
round4 v =
    let
        n =
            v * 10000

        i =
            toFloat (floor n)

        f =
            n - i

        r =
            if f > 0.5 - 1.0e-8 && f < 0.5 + 1.0e-8 then
                if modBy 2 (floor n) == 0 then
                    i

                else
                    i + 1

            else
                toFloat (round n)
    in
    r / 10000


rounded : (Cell -> Float) -> List Cell -> E.Value
rounded pick cells =
    E.list (pick >> round4 >> E.float) cells


ramp : Layer -> List String
ramp layer =
    case layer of
        Layer.Wind ->
            Config.windRamp

        _ ->
            Config.waveRamp


{-| `null` when the layer is neither wind nor waves, or no beach has both numbers.
-}
json : Model -> String
json model =
    case model.layer of
        Layer.Wind ->
            field model

        Layer.Waves ->
            field model

        _ ->
            "null"


field : Model -> String
field model =
    case Flow.buildField (readings model model.layer) (maxOf model.layer) of
        Nothing ->
            "null"

        Just f ->
            let
                cells =
                    Array.toList f.cells
            in
            E.object
                [ ( "kind", E.string (Layer.key model.layer) )
                , ( "w", E.int f.w )
                , ( "h", E.int f.h )
                , ( "x0", E.float f.x0 )
                , ( "x1", E.float f.x1 )
                , ( "y0", E.float f.y0 )
                , ( "y1", E.float f.y1 )
                , ( "u", rounded .u cells )
                , ( "v", rounded .v cells )
                , ( "m", rounded .m cells )
                , ( "a", rounded .a cells )
                , ( "ramp", E.list E.string (ramp model.layer) )
                ]
                |> E.encode 0
