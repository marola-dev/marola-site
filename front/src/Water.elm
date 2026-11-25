module Water exposing (Condition(..), Summary(..), Water, WaterPoint, conditionBand, conditionLabel, decoder, dotClass, parseCondition, parseSummary, pointDecoder, sampledText, summaryText)

import Band exposing (Band)
import DateFmt
import Dec exposing (required)
import I18n exposing (Locale)
import Json.Decode as D exposing (Decoder)
import Parse


{-| The agency's verdict on a sampling point.
-}
type Condition
    = Proper
    | Improper
    | Unclassified
    | Unknown String


type alias WaterPoint =
    { point : String
    , location : String
    , lat : Float
    , lon : Float
    , condition : Condition
    , sampledOn : String
    , enterococciPer100ml : Maybe Int
    , rain : Maybe String
    }


type alias Water =
    { summary : String
    , unfit : Bool
    , note : Maybe String
    , source : Maybe String
    , points : List WaterPoint
    }


parseCondition : String -> Condition
parseCondition value =
    case value of
        "proper" ->
            Proper

        "improper" ->
            Improper

        "unknown" ->
            Unclassified

        other ->
            Unknown other


conditionBand : Condition -> Band
conditionBand condition =
    case condition of
        Improper ->
            Band.Avoid

        Proper ->
            Band.Good

        _ ->
            Band.Unscored


conditionLabel : Condition -> Locale -> String
conditionLabel condition loc =
    case condition of
        Proper ->
            I18n.t loc "water.proper" []

        Improper ->
            I18n.t loc "water.improper" []

        _ ->
            I18n.t loc "water.unclassified" []


{-| A point's sample day ("2026-11-09") as the page prints a day.
-}
sampledText : WaterPoint -> Locale -> String
sampledText p loc =
    DateFmt.short p.sampledOn loc.language


pointDecoder : Decoder WaterPoint
pointDecoder =
    D.succeed WaterPoint
        |> required "point" D.string
        |> required "location" D.string
        |> required "lat" Dec.number
        |> required "lon" Dec.number
        |> required "condition" (Dec.enum parseCondition)
        |> required "sampled_on" D.string
        |> required "enterococci_per_100ml" (Dec.nullable Dec.int)
        |> required "rain" (Dec.nullable D.string)


decoder : Decoder Water
decoder =
    D.succeed Water
        |> required "summary" D.string
        |> required "unfit" D.bool
        |> required "note" (Dec.nullable D.string)
        |> required "source" (Dec.nullable D.string)
        |> required "points" (D.list pointDecoder)


{-| The board's summary, written in English by marola-app's `Swimability.waterVerdict`, read back
into its parts so each language can say it. `when` is the app's "d MMM" day ("9 Nov").
-}
type Summary
    = NoData
    | Stale String
    | AllUnfit { improper : String, total : String, when : String }
    | Mixed { proper : String, total : String, avoid : String, when : String }
    | NoVerdict { unknown : String, when : String }
    | Fit { proper : String, total : String, unknown : Maybe String, when : String }
    | Raw String


{-| "a (b)" as ( a, b ), when the text ends in its one closing parenthesis.
-}
paren : String -> Maybe ( String, String )
paren text =
    if String.endsWith ")" text then
        case String.indexes " (" text |> List.reverse |> List.head of
            Just i ->
                Just ( String.left i text, String.slice (i + 2) -1 text )

            Nothing ->
                Nothing

    else
        Nothing


{-| "a/b", both whole numbers.
-}
ratio : String -> Maybe ( String, String )
ratio text =
    case String.split "/" text of
        [ a, b ] ->
            case ( Parse.tryInt a, Parse.tryInt b ) of
                ( Just _, Just _ ) ->
                    Just ( a, b )

                _ ->
                    Nothing

        _ ->
            Nothing


parseSummary : String -> Summary
parseSummary text =
    let
        parsed =
            case paren text of
                Just ( "stale", when ) ->
                    Just (Stale when)

                Just ( "IMPRÓPRIA", inner ) ->
                    case String.split ", " inner of
                        [ counts, when ] ->
                            String.dropRight 4 counts
                                |> ratio
                                |> Maybe.andThen
                                    (\( a, b ) ->
                                        if String.endsWith " pts" counts then
                                            Just (AllUnfit { improper = a, total = b, when = when })

                                        else
                                            Nothing
                                    )

                        _ ->
                            Nothing

                Just ( "PRÓPRIA", inner ) ->
                    let
                        fit counts unknown when =
                            if String.endsWith " pts" counts then
                                String.dropRight 4 counts
                                    |> ratio
                                    |> Maybe.map (\( a, b ) -> Fit { proper = a, total = b, unknown = unknown, when = when })

                            else
                                Nothing
                    in
                    case String.split ", " inner of
                        [ counts, when ] ->
                            fit counts Nothing when

                        [ counts, unknown, when ] ->
                            if String.endsWith " unknown" unknown then
                                fit counts (Just (String.dropRight 8 unknown)) when

                            else
                                Nothing

                        _ ->
                            Nothing

                Just ( "no verdict", inner ) ->
                    case String.split ", " inner of
                        [ counts, when ] ->
                            if String.endsWith " pts unknown" counts then
                                Just (NoVerdict { unknown = String.dropRight 12 counts, when = when })

                            else
                                Nothing

                        _ ->
                            Nothing

                Just ( head, when ) ->
                    case String.split " PRÓPRIA — avoid " head of
                        [ counts, avoid ] ->
                            ratio counts |> Maybe.map (\( a, b ) -> Mixed { proper = a, total = b, avoid = avoid, when = when })

                        _ ->
                            Nothing

                Nothing ->
                    Nothing
    in
    if text == "no data" then
        NoData

    else
        Maybe.withDefault (Raw text) parsed


months : List String
months =
    [ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" ]


{-| The app's "9 Nov" in the page's own day format; anything else as it came.
-}
dayText : String -> Locale -> String
dayText when loc =
    case String.words when of
        [ day, month ] ->
            case ( Parse.tryInt day, List.indexedMap Tuple.pair months |> List.filter (\( _, m ) -> m == String.toLower (String.left 3 month)) |> List.head ) of
                ( Just d, Just ( i, _ ) ) ->
                    DateFmt.short ("2000-" ++ String.padLeft 2 '0' (String.fromInt (i + 1)) ++ "-" ++ String.padLeft 2 '0' (String.fromInt d)) loc.language

                _ ->
                    when

        _ ->
            when


summaryText : Water -> Locale -> String
summaryText water loc =
    let
        on when =
            I18n.arg "when" (dayText when loc)
    in
    case parseSummary water.summary of
        NoData ->
            I18n.t loc "water.no_data" []

        Stale when ->
            I18n.t loc "water.stale" [ on when ]

        AllUnfit r ->
            I18n.t loc "water.all_unfit" [ I18n.arg "improper" r.improper, I18n.arg "total" r.total, on r.when ]

        Mixed r ->
            I18n.t loc "water.mixed" [ I18n.arg "proper" r.proper, I18n.arg "total" r.total, I18n.arg "avoid" r.avoid, on r.when ]

        NoVerdict r ->
            I18n.t loc "water.no_verdict" [ I18n.arg "unknown" r.unknown, on r.when ]

        Fit r ->
            case r.unknown of
                Just unknown ->
                    I18n.t loc "water.fit_unknown" [ I18n.arg "proper" r.proper, I18n.arg "total" r.total, I18n.arg "unknown" unknown, on r.when ]

                Nothing ->
                    I18n.t loc "water.fit" [ I18n.arg "proper" r.proper, I18n.arg "total" r.total, on r.when ]

        Raw text ->
            text


dotBand : Water -> Band
dotBand water =
    if water.unfit then
        Band.Avoid

    else if water.summary == "no data" then
        Band.Unscored

    else
        Band.Good


dotClass : Water -> String
dotClass water =
    "wdot " ++ Band.cssClass (dotBand water)
