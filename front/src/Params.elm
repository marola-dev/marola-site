module Params exposing (Query, decode, delete, encode, get, parse, set, toString)

{-| The page's query string (`?area=&day=&beach=&layer=&lang=&beaches=&trails=`): state the visitor
can share, replaced in place on each change.
-}

import Bitwise


type alias Query =
    List ( String, String )


hexDigits : String
hexDigits =
    "0123456789ABCDEF"


utf8 : Char -> List Int
utf8 c =
    let
        code =
            Char.toCode c

        cont shift =
            Bitwise.or 0x80 (Bitwise.and 0x3F (Bitwise.shiftRightBy shift code))
    in
    if code < 0x80 then
        [ code ]

    else if code < 0x0800 then
        [ Bitwise.or 0xC0 (Bitwise.shiftRightBy 6 code), cont 0 ]

    else if code < 0x00010000 then
        [ Bitwise.or 0xE0 (Bitwise.shiftRightBy 12 code), cont 6, cont 0 ]

    else
        [ Bitwise.or 0xF0 (Bitwise.shiftRightBy 18 code), cont 12, cont 6, cont 0 ]


isUnreserved : Int -> Bool
isUnreserved b =
    (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || (b >= 48 && b <= 57) || b == 45 || b == 46 || b == 95 || b == 126


{-| Percent-encodes the UTF-8 bytes; only `A-Z a-z 0-9 - . _ ~` stay as they are.
-}
encode : String -> String
encode text =
    String.toList text
        |> List.concatMap utf8
        |> List.map
            (\b ->
                if isUnreserved b then
                    String.fromChar (Char.fromCode b)

                else
                    "%" ++ String.slice (b // 16) (b // 16 + 1) hexDigits ++ String.slice (modBy 16 b) (modBy 16 b + 1) hexDigits
            )
        |> String.concat


hexValue : Char -> Maybe Int
hexValue c =
    let
        code =
            Char.toCode c
    in
    if code >= 48 && code <= 57 then
        Just (code - 48)

    else if code >= 97 && code <= 102 then
        Just (code - 87)

    else if code >= 65 && code <= 70 then
        Just (code - 55)

    else
        Nothing


{-| UTF-8 bytes to text; a sequence that is not UTF-8 reads as U+FFFD, as .NET's decoder does.
-}
fromUtf8 : List Int -> String
fromUtf8 bytes =
    let
        isCont b =
            Bitwise.and b 0xC0 == 0x80

        bad =
            Char.fromCode 0xFFFD

        go rest acc =
            case rest of
                [] ->
                    List.reverse acc

                b :: tail ->
                    if b < 0x80 then
                        go tail (Char.fromCode b :: acc)

                    else
                        let
                            ( need, base, low ) =
                                if b >= 0xC2 && b <= 0xDF then
                                    ( 1, Bitwise.and b 0x1F, 0x80 )

                                else if b >= 0xE0 && b <= 0xEF then
                                    ( 2, Bitwise.and b 0x0F, 0x0800 )

                                else if b >= 0xF0 && b <= 0xF4 then
                                    ( 3, Bitwise.and b 0x07, 0x00010000 )

                                else
                                    ( 0, 0, 0 )

                            more =
                                List.take need tail
                        in
                        if need == 0 then
                            go tail (bad :: acc)

                        else if List.length more == need && List.all isCont more then
                            let
                                code =
                                    List.foldl (\x v -> Bitwise.or (Bitwise.shiftLeftBy 6 v) (Bitwise.and x 0x3F)) base more
                            in
                            if code < low || code > 0x0010FFFF || (code >= 0xD800 && code <= 0xDFFF) then
                                go tail (bad :: acc)

                            else
                                go (List.drop need tail) (Char.fromCode code :: acc)

                        else
                            go (List.drop (List.length (takeWhile isCont more)) tail) (bad :: acc)
    in
    String.fromList (go bytes [])


takeWhile : (a -> Bool) -> List a -> List a
takeWhile pred xs =
    case xs of
        x :: rest ->
            if pred x then
                x :: takeWhile pred rest

            else
                []

        [] ->
            []


{-| `+` is a space and `%XX` a byte; a `%` not followed by two hex digits stays as it is.
-}
decode : String -> String
decode text =
    let
        go chars acc =
            case chars of
                '%' :: h :: l :: rest ->
                    case ( hexValue h, hexValue l ) of
                        ( Just hi, Just lo ) ->
                            go rest ((hi * 16 + lo) :: acc)

                        _ ->
                            go (h :: l :: rest) (List.reverse (utf8 '%') ++ acc)

                '+' :: rest ->
                    go rest (32 :: acc)

                c :: rest ->
                    go rest (List.reverse (utf8 c) ++ acc)

                [] ->
                    List.reverse acc
    in
    fromUtf8 (go (String.toList text) [])


{-| `location.search` with or without its leading `?`.
-}
parse : String -> Query
parse search =
    let
        bare =
            if String.startsWith "?" search then
                String.dropLeft 1 search

            else
                search
    in
    String.split "&" bare
        |> List.filter (\pair -> pair /= "")
        |> List.map
            (\pair ->
                case String.indexes "=" pair of
                    i :: _ ->
                        ( decode (String.left i pair), decode (String.dropLeft (i + 1) pair) )

                    [] ->
                        ( decode pair, "" )
            )


get : Query -> String -> Maybe String
get query key =
    List.filter (\( k, _ ) -> k == key) query |> List.head |> Maybe.map Tuple.second


{-| Replaces the key where it stands, or adds it at the end.
-}
set : Query -> String -> String -> Query
set query key value =
    if List.any (\( k, _ ) -> k == key) query then
        List.map
            (\( k, v ) ->
                if k == key then
                    ( key, value )

                else
                    ( k, v )
            )
            query

    else
        query ++ [ ( key, value ) ]


delete : Query -> String -> Query
delete query key =
    List.filter (\( k, _ ) -> k /= key) query


toString : Query -> String
toString query =
    List.map (\( k, v ) -> encode k ++ "=" ++ encode v) query |> String.join "&"
