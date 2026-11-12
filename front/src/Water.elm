module Water exposing (Condition(..), Water, WaterPoint, conditionBand, conditionLabel, decoder, dotClass, parseCondition, summaryText)

import Band exposing (Band)
import Dec exposing (required)
import I18n exposing (Locale)
import Json.Decode as D exposing (Decoder)


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


{-| The agency's own words are Portuguese in every language; only the unclassified case goes
through the catalog.
-}
conditionLabel : Condition -> Locale -> String
conditionLabel condition loc =
    case condition of
        Proper ->
            "PRÓPRIA"

        Improper ->
            "IMPRÓPRIA"

        _ ->
            I18n.t loc "water.unclassified" []


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


{-| "no data" is the one summary the board writes in words rather than the agency's verdict.
-}
hasNoData : Water -> Bool
hasNoData water =
    water.summary == "no data"


summaryText : Water -> Locale -> String
summaryText water loc =
    if hasNoData water then
        I18n.t loc "water.no_data" []

    else
        water.summary


dotBand : Water -> Band
dotBand water =
    if water.unfit then
        Band.Avoid

    else if hasNoData water then
        Band.Unscored

    else
        Band.Good


dotClass : Water -> String
dotClass water =
    "wdot " ++ Band.cssClass (dotBand water)
