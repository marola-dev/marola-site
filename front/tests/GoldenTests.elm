module GoldenTests exposing (suite)

{-| The F# client's text, beach and flow functions against app/Tests/golden.json, which
the old ui.js, app.js and flow.js wrote.
-}

import Array
import Aspects exposing (Cell(..))
import Band
import Beach exposing (Selection(..))
import Board
import Dec
import Dict exposing (Dict)
import Flow
import Fmt
import Geo exposing (Point)
import I18n
import Icu exposing (Arg(..), Node(..))
import Json.Decode as D exposing (Decoder)
import Language
import Mercator
import NumFmt
import Rank
import Support exposing (allClose, beachNamed, catalog, check, close, langDecoder, locale, selection)
import Test exposing (Test, describe, test)
import Expect
import Water


nullable : Decoder a -> Decoder (Maybe a)
nullable =
    D.nullable


unless : Bool -> String -> Maybe String
unless ok label =
    if ok then
        Nothing

    else
        Just label


same : a -> a -> String -> Maybe String
same got want label =
    unless (got == want) (label ++ ": got " ++ Debug.toString got ++ ", want " ++ Debug.toString want)


pointDecoder : Decoder Point
pointDecoder =
    D.map2 Point (D.field "lat" D.float) (D.field "lon" D.float)


argsDecoder : Decoder (List ( String, Arg ))
argsDecoder =
    D.keyValuePairs (D.oneOf [ D.map Num D.float, D.map Text D.string ])
        |> D.map (List.sortBy Tuple.first)


nodeDecoder : Decoder Node
nodeDecoder =
    D.oneOf
        [ D.map Literal D.string
        , D.field "hash" D.bool |> D.map (\_ -> Hash)
        , D.map3 Argument
            (D.field "name" D.string)
            (D.maybe (D.field "type" D.string))
            (D.maybe (D.field "cases" (D.dict (D.list (D.lazy (\_ -> nodeDecoder))))) |> D.map (Maybe.withDefault Dict.empty))
        ]


parsedDecoder : Decoder (Result String (List Node))
parsedDecoder =
    D.oneOf [ D.field "ok" (D.list nodeDecoder) |> D.map Ok, D.field "error" D.string |> D.map Err ]


text : Test
text =
    describe "text"
        [ test "band" <|
            \_ ->
                check "band"
                    (D.map3 (\s u o -> ( s, u, o )) (D.field "score" (nullable D.int)) (D.field "unfit" D.bool) (D.field "out" D.string))
                    (\( s, u, o ) -> same (Band.cssClass (Band.ofScore s u)) o (Debug.toString ( s, u )))
        , test "number" <|
            \_ ->
                check "number"
                    (D.map5 (\l n a b o -> ( ( l, n ), ( a, b ), o )) (D.field "lang" langDecoder) (D.field "n" D.float) (D.field "min" D.int) (D.field "max" D.int) (D.field "out" D.string))
                    (\( ( l, n ), ( a, b ), o ) -> same (NumFmt.fixedDigits n l a b) o (Debug.toString ( l, n, ( a, b ) )))
        , test "fmt" <|
            \_ ->
                check "fmt"
                    (D.map5 (\l n u d o -> ( ( l, n ), ( u, d ), o )) (D.field "lang" langDecoder) (D.field "n" (nullable D.float)) (D.field "unit" D.string) (D.field "digits" (nullable D.int)) (D.field "out" D.string))
                    (\( ( l, n ), ( u, d ), o ) -> same (Fmt.value (locale l) n u (Maybe.withDefault 1 d)) o (Debug.toString ( l, n, u )))
        , test "waves text" <|
            \_ ->
                check "waves_text"
                    (D.map4 (\l m s o -> ( ( l, m ), s, o )) (D.field "lang" langDecoder) (D.field "wave_m" (nullable D.float)) (D.field "period_s" (nullable D.float)) (D.field "out" D.string))
                    (\( ( l, m ), s, o ) -> same (Fmt.waves (locale l) m s) o (Debug.toString ( l, m, s )))
        , test "word" <|
            \_ ->
                check "word"
                    (D.map4 (\l p v o -> ( ( l, p ), v, o )) (D.field "lang" langDecoder) (D.field "prefix" D.string) (D.field "value" D.string) (D.field "out" D.string))
                    (\( ( l, p ), v, o ) -> same (I18n.word (locale l) p v) o (Debug.toString ( l, p, v )))
        , test "compass" <|
            \_ ->
                check "compass"
                    (D.map3 (\l d o -> ( l, d, o )) (D.field "lang" langDecoder) (D.field "deg" D.float) (D.field "out" D.string))
                    (\( l, d, o ) -> same (I18n.word (locale l) "dir." (Geo.compassKey d)) o (Debug.toString ( l, d )))
        , test "condition label" <|
            \_ ->
                check "cond_label"
                    (D.map3 (\l c o -> ( l, c, o )) (D.field "lang" langDecoder) (D.field "condition" D.string) (D.field "out" D.string))
                    (\( l, c, o ) -> same (Water.conditionLabel (Water.parseCondition c) (locale l)) o c)
        , test "water summary and dot" <|
            \_ ->
                check "water"
                    (D.map4 (\l w s d -> ( ( l, w ), s, d )) (D.field "lang" langDecoder) (D.field "water" Water.decoder) (D.field "summary" D.string) (D.field "dot" D.string))
                    (\( ( l, w ), s, d ) -> same ( Water.summaryText w (locale l), Water.dotClass w ) ( s, d ) w.summary)
        , test "lookup" <|
            \_ ->
                check "lookup"
                    (D.map3 (\l k o -> ( l, k, o )) (D.field "lang" langDecoder) (D.field "key" D.string) (D.field "out" (nullable D.string)))
                    (\( l, k, o ) -> same (I18n.lookup catalog l k) o k)
        , test "resolve language" <|
            \_ ->
                check "resolve_lang"
                    (D.map4 (\p s ls o -> ( ( p, s ), ls, o )) (D.field "param" (nullable D.string)) (D.field "stored" (nullable D.string)) (D.field "languages" (D.list D.string)) (D.field "out" D.string))
                    (\( ( p, s ), ls, o ) -> same (Language.tag (Language.resolve p s ls Language.all)) o (Debug.toString ( p, s, ls )))
        , test "icu parse" <|
            \_ ->
                check "icu_parse"
                    (D.map2 Tuple.pair (D.field "src" D.string) (D.field "out" parsedDecoder))
                    (\( src, want ) -> same (Icu.parse src) want src)
        , test "icu format" <|
            \_ ->
                check "icu_format"
                    (D.map4 (\l s a o -> ( ( l, s ), a, o )) (D.field "lang" langDecoder) (D.field "src" D.string) (D.field "args" argsDecoder) (D.field "out" D.string))
                    (\( ( l, s ), a, o ) ->
                        case Icu.parse s of
                            Ok nodes ->
                                same (Icu.format nodes a l Nothing) o s

                            Err e ->
                                Just e
                    )
        , test "t over the whole catalog" <|
            \_ ->
                check "t_all"
                    (D.map3 (\l k o -> ( l, k, o )) (D.field "lang" langDecoder) (D.field "key" D.string) (D.field "out" D.string))
                    (\( l, k, o ) -> same (I18n.t (locale l) k []) o k)
        , test "t with arguments" <|
            \_ ->
                check "t"
                    (D.map4 (\l k a o -> ( ( l, k ), a, o )) (D.field "lang" langDecoder) (D.field "key" D.string) (D.field "args" argsDecoder) (D.field "out" D.string))
                    (\( ( l, k ), a, o ) -> same (I18n.t (locale l) k a) o k)
        , test "t falls back to the source language" <|
            \_ ->
                let
                    byLanguage =
                        Support.goldenOne "fallback_catalog" (D.dict I18n.messagesDecoder)
                in
                check "fallback"
                    (D.map4 (\l k a o -> ( ( l, k ), a, o )) (D.field "lang" langDecoder) (D.field "key" D.string) (D.field "args" argsDecoder) (D.field "out" D.string))
                    (\( ( l, k ), a, o ) -> same (I18n.t { catalog = byLanguage, language = l } k a) o k)
        , test "every catalog message parses" <|
            \_ ->
                catalog
                    |> Dict.toList
                    |> List.concatMap (\( lang, m ) -> Dict.toList m |> List.filterMap (\( k, v ) -> unless (isOk (Icu.parse v)) (lang ++ " " ++ k)))
                    |> Expect.equal []
        ]


isOk : Result e a -> Bool
isOk r =
    case r of
        Ok _ ->
            True

        Err _ ->
            False


type alias ShownCase =
    { variant : String, sel : Maybe String, shown : Maybe ( String, Int ), notes : Maybe ( List String, Bool ), entryH : Maybe String }


beach : Test
beach =
    describe "beach"
        [ test "haversine" <|
            \_ ->
                -- sin and asin come from two different libms, so the last digits may differ
                check "haversine"
                    (D.map3 (\a b km -> ( a, b, km )) (D.field "a" pointDecoder) (D.field "b" pointDecoder) (D.field "km" D.float))
                    (\( a, b, km ) -> unless (close (Geo.haversineKm a b) km 1.0e-12) (Debug.toString ( a, b )))
        , test "shown and hourEntry" <|
            \_ ->
                let
                    shownDecoder =
                        D.map4 (\h s n b -> ( h, s, ( n, b ) ))
                            (D.field "h" D.string)
                            (D.field "score" D.int)
                            (D.field "notes" (D.list D.string))
                            (D.maybe (D.field "best" D.bool) |> D.map (Maybe.withDefault False))
                in
                check "shown"
                    (D.map4 (\v s sh e -> ( ( v, s ), sh, e )) (D.field "variant" D.string) (D.field "selection" (nullable D.string)) (D.field "shown" (Dec.lossy shownDecoder)) (D.field "entry_h" (nullable D.string)))
                    (\( ( v, sel ), want, entryH ) ->
                        let
                            b =
                                beachNamed v

                            s =
                                Beach.shown b (selection sel)
                        in
                        same
                            ( Maybe.map (\x -> ( x.h, x.score, ( x.notes, x.best ) )) s, Beach.hourEntry b s |> Maybe.map .h )
                            ( want, entryH )
                            (Debug.toString ( v, sel ))
                    )
        , test "aspects" <|
            \_ ->
                let
                    mark =
                        Dec.lossy (D.map2 Tuple.pair (D.field "cls" D.string) (D.field "dot" (nullable D.string)))
                in
                check "aspects"
                    (D.map6 (\l v s h c m -> { lang = l, variant = v, sel = s, head = h, cells = c, marks = m })
                        (D.field "lang" langDecoder)
                        (D.field "variant" D.string)
                        (D.field "selection" (nullable D.string))
                        (D.field "head" D.string)
                        (D.field "cells" (D.list D.string))
                        (D.field "marks" (D.list mark))
                    )
                    (\c ->
                        let
                            b =
                                beachNamed c.variant

                            got =
                                Aspects.ofBeach b (Beach.shown b (selection c.sel)) (locale c.lang)

                            -- The water cell is the only one the old markup gave a class and a dot.
                            quality =
                                c.marks
                                    |> List.filterMap
                                        (\m ->
                                            case m of
                                                Just ( cls, Just dot ) ->
                                                    Just ( String.contains "unfit" cls, dot )

                                                _ ->
                                                    Nothing
                                        )
                                    |> List.head

                            gotQuality =
                                got.cells
                                    |> List.filterMap
                                        (\cell ->
                                            case cell of
                                                Quality _ unfit dot ->
                                                    Just ( unfit, dot )

                                                _ ->
                                                    Nothing
                                        )
                                    |> List.head
                        in
                        same ( got.head, List.map Aspects.cellText got.cells, gotQuality ) ( c.head, c.cells, quality ) (Debug.toString ( c.lang, c.variant, c.sel ))
                    )
        , test "isPast" <|
            \_ ->
                check "is_past"
                    (D.map5 (\d t g h o -> ( ( d, t ), ( g, h ), o )) (D.field "day" D.string) (D.field "today" D.string) (D.field "generated_at" D.string) (D.field "h" D.string) (D.field "out" D.bool))
                    (\( ( day, today ), ( generatedAt, h ), o ) ->
                        let
                            b =
                                { schema = 2
                                , area = "x"
                                , day = day
                                , today = today
                                , generatedAt = generatedAt
                                , sources = { beaches = "", forecast = "", water = Nothing }
                                , lore = Nothing
                                , beaches = []
                                , trails = []
                                }
                        in
                        same (Board.isPast b h) o (Debug.toString ( day, today, h ))
                    )
        , test "ranked" <|
            \_ ->
                check "ranked"
                    (D.map6 (\v hs i here n km -> { variants = v, hours = hs, index = i, here = here, names = n, km = km })
                        (D.field "variants" (D.list D.string))
                        (D.field "hours" (D.list D.string))
                        (D.field "index" (Dec.lossy D.int))
                        (D.field "here" (Dec.lossy pointDecoder))
                        (D.field "names" (D.list D.string))
                        (D.field "km" (Dec.lossy (D.list D.float)))
                    )
                    (\c ->
                        let
                            beaches =
                                List.map beachNamed c.variants

                            sel =
                                case c.index of
                                    Nothing ->
                                        BestHour

                                    Just i ->
                                        selection (List.head (List.drop i c.hours))
                        in
                        case c.here of
                            Nothing ->
                                same (Rank.byScore beaches sel |> List.map .name) c.names "by score"

                            Just here ->
                                let
                                    got =
                                        Rank.byDistance beaches here
                                in
                                case same (List.map (Tuple.first >> .name) got) c.names "by distance" of
                                    Nothing ->
                                        unless (allClose (List.map Tuple.second got) (Maybe.withDefault [] c.km) 1.0e-12) "km"

                                    failure ->
                                        failure
                    )
        ]


flow : Test
flow =
    describe "flow"
        [ test "mercator" <|
            \_ ->
                check "mercator"
                    (D.map3 (\f i o -> ( f, i, o )) (D.field "fn" D.string) (D.field "in" D.float) (D.field "out" D.float))
                    (\( name, input, out ) ->
                        let
                            fn =
                                case name of
                                    "x" ->
                                        Just Mercator.x

                                    "y" ->
                                        Just Mercator.y

                                    "lon_of" ->
                                        Just Mercator.lonOf

                                    "lat_of" ->
                                        Just Mercator.latOf

                                    _ ->
                                        Nothing
                        in
                        case fn of
                            Just f ->
                                unless (close (f input) out 1.0e-12) (Debug.toString ( name, input, f input ))

                            Nothing ->
                                Just ("unknown mercator function " ++ name)
                    )
        , test "field" <|
            \_ ->
                let
                    reading =
                        D.map4 Flow.Reading (D.field "lon" D.float) (D.field "lat" D.float) (D.field "mag" (nullable D.float)) (D.field "dir" (nullable D.float))

                    cell =
                        D.map4 Flow.Cell (D.field "u" D.float) (D.field "v" D.float) (D.field "m" D.float) (D.field "a" D.float)

                    expected =
                        D.map5 (\x0 x1 y0 y1 cs -> ( [ x0, x1, y0, y1 ], cs ))
                            (D.field "x0" D.float)
                            (D.field "x1" D.float)
                            (D.field "y0" D.float)
                            (D.field "y1" D.float)
                            (D.field "cells" (D.list (D.map2 Tuple.pair (D.field "n" D.int) cell)))

                    cellClose a b =
                        allClose [ a.u, a.v, a.m, a.a ] [ b.u, b.v, b.m, b.a ] 1.0e-5
                in
                check "field"
                    (D.map3 (\m p f -> ( m, p, f )) (D.field "max" D.float) (D.field "points" (D.list reading)) (D.field "field" (Dec.lossy expected)))
                    (\( top, points, want ) ->
                        case ( Flow.buildField points top, want ) of
                            ( Nothing, Nothing ) ->
                                Nothing

                            ( Just field, Just ( bounds, cells ) ) ->
                                if not (allClose [ field.x0, field.x1, field.y0, field.y1 ] bounds 1.0e-12) then
                                    Just "bounds"

                                else
                                    cells
                                        |> List.filter (\( n, c ) -> Array.get n field.cells |> Maybe.map (cellClose c) |> Maybe.withDefault False |> not)
                                        |> List.head
                                        |> Maybe.map (\( n, _ ) -> "cell " ++ String.fromInt n)

                            _ ->
                                Just "null does not match"
                    )
        ]


suite : Test
suite =
    describe "golden" [ text, beach, flow ]
