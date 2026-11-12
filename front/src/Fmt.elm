module Fmt exposing (num, signed, value, waves)

{-| How app.js writes a number with its unit. -}

import I18n exposing (Locale)
import NumFmt


{-| Exactly `digits` fraction digits, in the page's language.
-}
num : Locale -> Float -> Int -> String
num loc n digits =
    NumFmt.fixedDigits n loc.language digits digits


{-| app.js `.replace(' ', ' ')` changes the first space only.
-}
firstSpaceToNbsp : String -> String
firstSpaceToNbsp unit =
    case String.indexes " " unit of
        i :: _ ->
            String.left i unit ++ "\u{00A0}" ++ String.dropLeft (i + 1) unit

        [] ->
            unit


{-| A value and its unit, kept together by a no-break space; no value reads "n/a".
-}
value : Locale -> Maybe Float -> String -> Int -> String
value loc n unit digits =
    case n of
        Nothing ->
            I18n.t loc "common.na" []

        Just x ->
            num loc x digits ++ firstSpaceToNbsp unit


waves : Locale -> Maybe Float -> Maybe Float -> String
waves loc waveM periodS =
    I18n.t loc
        "cell.waves"
        [ I18n.arg "m" (value loc waveM " m" 1)
        , I18n.arg "every"
            (if periodS == Nothing then
                "no"

             else
                "yes"
            )
        , I18n.arg "s" (value loc periodS " s" 0)
        ]


{-| `signDisplay: 'exceptZero'`: the tide's height above the mean level.
-}
signed : Locale -> Float -> Int -> String
signed loc n digits =
    let
        body =
            num loc (abs n) digits
    in
    if body == num loc 0 digits then
        body

    else if n < 0 then
        "-" ++ body

    else
        "+" ++ body
