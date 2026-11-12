module Parse exposing (shortest, tryFloat, tryInt)

{-| Strict number parsing: Elm's own `String.toFloat` accepts forms the board never writes.
-}


isDigits : String -> Bool
isDigits s =
    s /= "" && String.all Char.isDigit s


afterSign : String -> String
afterSign s =
    if String.startsWith "-" s || String.startsWith "+" s then
        String.dropLeft 1 s

    else
        s


{-| An optional sign, then digits only.
-}
tryInt : String -> Maybe Int
tryInt s =
    if isDigits (afterSign s) then
        String.toInt s

    else
        Nothing


{-| An optional sign, digits, an optional fraction, an optional exponent.
-}
tryFloat : String -> Maybe Float
tryFloat s =
    let
        ( mantissa, exponent ) =
            case String.indexes "e" (String.toLower s) of
                i :: _ ->
                    ( String.left i s, Just (String.dropLeft (i + 1) s) )

                [] ->
                    ( s, Nothing )

        body =
            afterSign mantissa

        mantissaOk =
            case String.split "." body of
                [ whole ] ->
                    isDigits whole

                [ whole, fraction ] ->
                    isDigits whole && isDigits fraction

                _ ->
                    False

        exponentOk =
            case exponent of
                Nothing ->
                    True

                Just e ->
                    isDigits (afterSign e)
    in
    if mantissaOk && exponentOk then
        String.toFloat (normalise s)

    else
        Nothing



-- String.toFloat refuses a leading "+".


normalise : String -> String
normalise s =
    if String.startsWith "+" s then
        String.dropLeft 1 s

    else
        s


{-| JavaScript's `String(n)`, which `String.fromFloat` is.
-}
shortest : Float -> String
shortest =
    String.fromFloat
