module Aspects exposing (Aspects, Cell(..), Facility, cellText, ofBeach)

{-| The aspect cells of a beach tooltip and card: app.js `aspectsHtml` as data. -}

import Beach exposing (Beach, Facilities)
import Fmt
import Geo
import Hour exposing (Hour, Shown)
import I18n exposing (Locale)
import Level exposing (Level)
import Water
import WindLevel


type alias Facility =
    { key : String, text : String }


{-| `Wind`'s second part is the compass word, kept apart so the page can mark it up.
-}
type Cell
    = Wind String (Maybe String)
    | WaterTemp String
    | Waves String
    | Jellyfish String
    | Whales String
    | Quality String Bool String
    | FacilityCounts (List Facility)


{-| `cells` is empty when the beach is dark at that hour.
-}
type alias Aspects =
    { head : String, cells : List Cell }


cellText : Cell -> String
cellText c =
    case c of
        Wind t Nothing ->
            t

        Wind t (Just dir) ->
            t ++ " " ++ dir

        WaterTemp t ->
            t

        Waves t ->
            t

        Jellyfish t ->
            t

        Whales t ->
            t

        Quality t _ _ ->
            t

        FacilityCounts parts ->
            List.map .text parts |> String.join " · "


yesNo : Bool -> String
yesNo flag =
    if flag then
        "yes"

    else
        "no"


headText : Maybe Shown -> Locale -> String
headText shown loc =
    case shown of
        Just s ->
            I18n.t loc "tip.at" [ I18n.numberArg "score" (toFloat s.score), I18n.arg "h" s.h ]

        Nothing ->
            I18n.t loc "tip.dark" []


levelWord : Locale -> Level -> String
levelWord loc level =
    I18n.word loc "lvl." (Level.toString level)


windCell : Beach -> Hour -> Shown -> Locale -> Cell
windCell beach e s loc =
    let
        kmh =
            Fmt.value loc e.windKmh " km/h" 0

        -- An older board has no band: the number only, no word.
        reading =
            case Maybe.map WindLevel.toString e.windLevel of
                Just "" ->
                    I18n.t loc "cell.wind" [ I18n.arg "v" kmh ]

                Nothing ->
                    I18n.t loc "cell.wind" [ I18n.arg "v" kmh ]

                Just raw ->
                    I18n.word loc "wind." raw ++ ", " ++ kmh
    in
    case ( s.best, beach.sea.windDirDeg ) of
        ( True, Just deg ) ->
            Wind reading (Just (I18n.word loc "dir." (Geo.compassKey deg)))

        _ ->
            Wind reading Nothing


whalesText : Beach -> Hour -> Locale -> String
whalesText beach e loc =
    let
        peak =
            case beach.whales.peak of
                Just p ->
                    p /= "" && p /= e.h

                Nothing ->
                    False
    in
    I18n.t loc
        "cell.whales"
        [ I18n.arg "level" (levelWord loc e.whales)
        , I18n.arg "best" (yesNo peak)
        , I18n.arg "peak" (Maybe.withDefault "" beach.whales.peak)
        ]


facilityParts : Maybe Facilities -> Locale -> List Facility
facilityParts facilities loc =
    case facilities of
        Nothing ->
            []

        Just f ->
            [ ( "parking", f.parking ), ( "toilets", f.toilets ), ( "shower", f.shower ), ( "lifeguard", f.lifeguard ) ]
                |> List.filterMap
                    (\( key, count ) ->
                        count |> Maybe.map (\n -> { key = key, text = I18n.t loc ("fac." ++ key) [ I18n.numberArg "n" (toFloat n) ] })
                    )


cells : Beach -> Hour -> Shown -> Locale -> List Cell
cells beach e s loc =
    let
        facilities =
            case facilityParts beach.facilities loc of
                [] ->
                    []

                parts ->
                    [ FacilityCounts parts ]

        period =
            if s.best then
                beach.sea.periodS

            else
                Nothing
    in
    [ windCell beach e s loc
    , WaterTemp (I18n.t loc "cell.water" [ I18n.arg "v" (Fmt.value loc e.seaTempC " °C" 1) ])
    , Waves (Fmt.waves loc e.waveM period)
    , Jellyfish (I18n.t loc "cell.jellyfish" [ I18n.arg "level" (levelWord loc e.jellyfish) ])
    , Whales (whalesText beach e loc)
    , Quality (Water.summaryText beach.water loc) beach.water.unfit (Water.dotClass beach.water)
    ]
        ++ facilities


ofBeach : Beach -> Maybe Shown -> Locale -> Aspects
ofBeach beach shown loc =
    let
        head =
            beach.name ++ " · " ++ headText shown loc
    in
    case ( Beach.hourEntry beach shown, shown ) of
        ( Just entry, Just s ) ->
            { head = head, cells = cells beach entry s loc }

        _ ->
            { head = head, cells = [] }
