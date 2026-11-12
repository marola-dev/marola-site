module NumFmt exposing (fixedDigits, format)

{-| Number formatting for pt-BR and en without Intl. It rounds the shortest decimal text of the
float, half away from zero, as ECMA-402 does, so 1.005 prints 1.01.
-}

import Language exposing (Language(..))
import Parse


separators : Language -> ( String, String )
separators language =
    case language of
        PtBr ->
            ( ".", "," )

        En ->
            ( ",", "." )


{-| The significant digits and the count of digits before the point: 0.DIGITS \* 10^point.
-}
decimalDigits : Float -> ( List Int, Int )
decimalDigits n =
    let
        text =
            Parse.shortest n

        ( mantissa, exponent ) =
            case String.split "e" text of
                [ m, e ] ->
                    ( m, Parse.tryInt e |> Maybe.withDefault 0 )

                _ ->
                    ( text, 0 )

        ( whole, fraction ) =
            case String.split "." mantissa of
                [ w, f ] ->
                    ( w, f )

                _ ->
                    ( mantissa, "" )

        all =
            String.toList (whole ++ fraction) |> List.map (\c -> Char.toCode c - 48)

        strip digits point =
            case digits of
                0 :: rest ->
                    strip rest (point - 1)

                _ ->
                    if List.all ((==) 0) digits then
                        ( [], 0 )

                    else
                        ( digits, point )
    in
    strip all (String.length whole + exponent)


increment : List Int -> Int -> ( List Int, Int )
increment kept point =
    let
        folder digit ( done, carry ) =
            if carry && digit == 9 then
                ( 0 :: done, True )

            else if carry then
                ( (digit + 1) :: done, False )

            else
                ( digit :: done, False )
    in
    case List.foldr folder ( [], True ) kept of
        ( done, True ) ->
            ( 1 :: done, point + 1 )

        ( done, False ) ->
            ( done, point )


round : List Int -> Int -> Int -> ( List Int, Int )
round digits point max =
    let
        keep =
            point + max
    in
    if keep < 0 then
        ( [], 0 )

    else if keep >= List.length digits then
        ( digits, point )

    else
        let
            kept =
                List.take keep digits

            next =
                List.drop keep digits |> List.head |> Maybe.withDefault 0
        in
        if next >= 5 then
            increment kept point

        else
            ( kept, point )


digitsText : List Int -> String
digitsText =
    List.map String.fromInt >> String.concat


wholePart : List Int -> Int -> String
wholePart digits point =
    if point <= 0 then
        "0"

    else
        (digits ++ List.repeat point 0) |> List.take point |> digitsText


trimTrailingZeros : List Int -> Int -> List Int
trimTrailingZeros digits min =
    let
        go reversed =
            case reversed of
                0 :: rest ->
                    if List.length reversed > min then
                        go rest

                    else
                        reversed

                _ ->
                    reversed
    in
    List.reverse (go (List.reverse digits))


fractionPart : List Int -> Int -> Int -> String
fractionPart digits point min =
    let
        leading =
            if point < 0 then
                List.repeat -point 0

            else
                []

        afterPoint =
            if point < 0 then
                digits

            else
                List.drop point digits

        trimmed =
            trimTrailingZeros (leading ++ afterPoint) min
    in
    digitsText (trimmed ++ List.repeat (Basics.max 0 (min - List.length trimmed)) 0)


grouped : String -> String -> String
grouped whole separator =
    let
        first =
            case modBy 3 (String.length whole) of
                0 ->
                    3

                k ->
                    k

        loop rest take acc =
            if rest == "" then
                List.reverse acc

            else
                loop (String.dropLeft take rest) 3 (String.left take rest :: acc)
    in
    loop whole first [] |> String.join separator


{-| Like Intl's minimumFractionDigits and maximumFractionDigits.
-}
fixedDigits : Float -> Language -> Int -> Int -> String
fixedDigits n language min max =
    let
        ( d0, p0 ) =
            decimalDigits (abs n)

        ( digits, point ) =
            round d0 p0 max

        whole =
            wholePart digits point

        fraction =
            fractionPart digits point min

        ( group, mark ) =
            separators language

        body =
            if fraction == "" then
                grouped whole group

            else
                grouped whole group ++ mark ++ fraction
    in
    if n < 0 then
        "-" ++ body

    else
        body


{-| `new Intl.NumberFormat(locale).format(n)`: up to 3 fraction digits.
-}
format : Float -> Language -> String
format n language =
    fixedDigits n language 0 3
