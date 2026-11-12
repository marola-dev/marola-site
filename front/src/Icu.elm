module Icu exposing (Arg(..), Node(..), format, parse)

{-| The ICU message subset the catalogs use: `{arg}`, `{n, plural, ...}` with `#`, and
`{x, select, ...}`. A port of ui.js `parse` and `format`; error positions count UTF-16 units.
-}

import Dict exposing (Dict)
import Language exposing (Language(..))
import NumFmt
import Parse


type Node
    = Literal String
    | Hash
    | Argument String (Maybe String) (Dict String (List Node))


type Arg
    = Num Float
    | Text String


{-| The source as UTF-16 units, so a position means what it means in ui.js.
-}
type alias Cursor =
    { source : String, units : List Char, pos : Int }


at : Cursor -> Maybe Char
at cursor =
    List.head cursor.units


advance : Cursor -> Cursor
advance cursor =
    case cursor.units of
        c :: rest ->
            { cursor | units = rest, pos = cursor.pos + width c }

        [] ->
            cursor


width : Char -> Int
width c =
    if Char.toCode c > 0xFFFF then
        2

    else
        1


fail : Cursor -> String -> Result String a
fail cursor expected =
    Err ("i18n: expected " ++ expected ++ " at " ++ String.fromInt cursor.pos ++ " in " ++ cursor.source)


{-| JavaScript's `\s`.
-}
isSpace : Char -> Bool
isSpace c =
    let
        code =
            Char.toCode c
    in
    List.member code [ 0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF ]
        || (code >= 0x2000 && code <= 0x200A)


skipSpaces : Cursor -> Cursor
skipSpaces cursor =
    case at cursor of
        Just c ->
            if isSpace c then
                skipSpaces (advance cursor)

            else
                cursor

        Nothing ->
            cursor


takeName : Cursor -> ( String, Cursor )
takeName cursor =
    let
        go cur acc =
            case at cur of
                Just c ->
                    if isSpace c || c == ',' || c == '{' || c == '}' then
                        ( String.fromList (List.reverse acc), cur )

                    else
                        go (advance cur) (c :: acc)

                Nothing ->
                    ( String.fromList (List.reverse acc), cur )
    in
    go cursor []


word : Cursor -> Result String ( String, Cursor )
word cursor =
    let
        ( name, after ) =
            takeName (skipSpaces cursor)
    in
    if name == "" then
        fail cursor "a name"

    else
        Ok ( name, skipSpaces after )


expect : Cursor -> Char -> Result String Cursor
expect cursor char =
    if at cursor == Just char then
        Ok (advance cursor)

    else
        fail cursor (String.fromChar char)


flush : List Node -> List Char -> List Node
flush out text =
    case text of
        [] ->
            out

        _ ->
            Literal (String.fromList (List.reverse text)) :: out


message : Cursor -> Bool -> Result String ( List Node, Cursor )
message start inPlural =
    let
        loop cursor out text =
            case at cursor of
                Nothing ->
                    Ok ( List.reverse (flush out text), cursor )

                Just '}' ->
                    Ok ( List.reverse (flush out text), cursor )

                Just '{' ->
                    argument (advance cursor) inPlural
                        |> Result.andThen (\( node, after ) -> loop after (node :: flush out text) [])

                Just '#' ->
                    if inPlural then
                        loop (advance cursor) (Hash :: flush out text) []

                    else
                        loop (advance cursor) out ('#' :: text)

                Just c ->
                    loop (advance cursor) out (c :: text)
    in
    loop start [] []


argument : Cursor -> Bool -> Result String ( Node, Cursor )
argument start inPlural =
    word start
        |> Result.andThen
            (\( name, cursor ) ->
                if at cursor == Just ',' then
                    word (advance cursor)
                        |> Result.andThen
                            (\( kind, c1 ) ->
                                expect c1 ','
                                    |> Result.andThen
                                        (\c2 ->
                                            cases (skipSpaces c2) (inPlural || kind == "plural") Dict.empty
                                                |> Result.andThen
                                                    (\( found, c3 ) ->
                                                        expect c3 '}'
                                                            |> Result.map (\c4 -> ( Argument name (Just kind) found, c4 ))
                                                    )
                                        )
                            )

                else
                    expect cursor '}' |> Result.map (\c -> ( Argument name Nothing Dict.empty, c ))
            )


cases : Cursor -> Bool -> Dict String (List Node) -> Result String ( Dict String (List Node), Cursor )
cases cursor inPlural acc =
    case at cursor of
        Nothing ->
            Ok ( acc, cursor )

        Just '}' ->
            Ok ( acc, cursor )

        _ ->
            word cursor
                |> Result.andThen
                    (\( caseKey, c1 ) ->
                        expect c1 '{'
                            |> Result.andThen
                                (\c2 ->
                                    message c2 inPlural
                                        |> Result.andThen
                                            (\( nodes, c3 ) ->
                                                expect c3 '}'
                                                    |> Result.andThen (\c4 -> cases (skipSpaces c4) inPlural (Dict.insert caseKey nodes acc))
                                            )
                                )
                    )


parse : String -> Result String (List Node)
parse source =
    message { source = source, units = String.toList source, pos = 0 } False
        |> Result.andThen
            (\( nodes, cursor ) ->
                if List.isEmpty cursor.units then
                    Ok nodes

                else
                    Err ("i18n: unbalanced } in " ++ source)
            )


numberOf : Maybe Arg -> Maybe Float
numberOf value =
    case value of
        Just (Num f) ->
            Just f

        Just (Text s) ->
            Parse.tryFloat s

        Nothing ->
            Nothing


{-| A case key for a value: JavaScript's `String(v)`.
-}
key : Maybe Arg -> String
key value =
    case value of
        Just (Num f) ->
            String.fromFloat f

        Just (Text s) ->
            s

        Nothing ->
            "undefined"


isWhole : Float -> Bool
isWhole n =
    fractional n == 0


fractional : Float -> Float
fractional n =
    n - toFloat (floor n)


{-| CLDR 42+: a whole multiple of a million takes "many" in Portuguese.
-}
pluralCategory : Language -> Maybe Arg -> String
pluralCategory language value =
    case numberOf value of
        Nothing ->
            "other"

        Just f ->
            let
                n =
                    abs f
            in
            case language of
                En ->
                    if n == 1 then
                        "one"

                    else
                        "other"

                PtBr ->
                    if n < 2 then
                        "one"

                    else if isWhole n && fractional (n / 1000000) == 0 then
                        "many"

                    else
                        "other"


firstCase : Dict String (List Node) -> List String -> List Node
firstCase found keys =
    case List.filterMap (\k -> Dict.get k found) keys of
        nodes :: _ ->
            nodes

        [] ->
            Dict.get "other" found |> Maybe.withDefault []


hashText : Maybe Arg -> Language -> String
hashText value language =
    case numberOf value of
        Just f ->
            NumFmt.format f language

        Nothing ->
            "NaN"


lookupArg : String -> List ( String, Arg ) -> Maybe Arg
lookupArg name args =
    List.filter (\( k, _ ) -> k == name) args |> List.head |> Maybe.map Tuple.second


{-| ui.js `format`: `n` is the plural number that `#` prints.
-}
format : List Node -> List ( String, Arg ) -> Language -> Maybe Arg -> String
format nodes args language n =
    nodes
        |> List.map
            (\node ->
                case node of
                    Literal text ->
                        text

                    Hash ->
                        hashText n language

                    Argument name Nothing _ ->
                        case lookupArg name args of
                            Nothing ->
                                "{" ++ name ++ "}"

                            Just (Num f) ->
                                NumFmt.format f language

                            Just (Text s) ->
                                s

                    Argument name (Just "plural") found ->
                        let
                            v =
                                lookupArg name args
                        in
                        format (firstCase found [ "=" ++ key v, pluralCategory language v ]) args language v

                    Argument name (Just _) found ->
                        format (firstCase found [ key (lookupArg name args) ]) args language n
            )
        |> String.concat
