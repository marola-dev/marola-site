module Mercator exposing (latOf, lonOf, x, y)

{-| Web Mercator in unit space (0..1 across the world), as flow.js draws in.
-}


x : Float -> Float
x lon =
    (lon + 180) / 360


y : Float -> Float
y lat =
    let
        -- The projection's log reaches infinity at the poles.
        clamped =
            clamp -89.999999 89.999999 lat

        s =
            sin (clamped * pi / 180)
    in
    0.5 - logBase e ((1 + s) / (1 - s)) / (4 * pi)


lonOf : Float -> Float
lonOf v =
    v * 360 - 180


latOf : Float -> Float
latOf v =
    360 / pi * atan (Basics.e ^ ((1 - 2 * v) * pi)) - 90
