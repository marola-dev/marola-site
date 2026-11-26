module Model exposing (DayEntry, MapState(..), Model, Panel(..), Status(..), TrailsFile(..), WaterFileState(..), beaches, initial, lagoonWater, trails)

import Area exposing (Area)
import Beach exposing (Beach, Selection)
import Board exposing (Board)
import Geo exposing (Point)
import I18n exposing (Locale)
import Language exposing (Language)
import Layer exposing (Layer)
import Params exposing (Query)
import Trails exposing (Trails)
import Water exposing (Condition(..), Water, WaterPoint)
import WaterFile


{-| What the map is doing. A failed map keeps the page usable through the list.
-}
type MapState
    = MapNone
    | MapLoading
    | MapReady
    | MapFailed String


{-| The footer's line while the page loads or when it could not.
-}
type Status
    = Loading String
    | Failed String Bool
    | NoAreas
    | TooNew Int
    | Idle


type TrailsFile
    = TrailsPending
    | TrailsLoaded Trails
      -- No file for the area: the board's own trails stand in.
    | TrailsMissing


{-| The area's own sampling points (`data/water/<area>.json`): the points the board leaves out.
-}
type WaterFileState
    = WaterFilePending
    | WaterFileLoaded WaterFile.WaterFile
    | WaterFileMissing


{-| The one panel that may fill the map's left edge.
-}
type Panel
    = Closed
    | BeachList
    | TrailList


{-| One entry of `data/<area>/latest.json`.
-}
type alias DayEntry =
    { date : String, file : String }


type alias Model =
    { loc : Locale
    , catalogsPending : Int
    , path : String
    , query : Query
    , areas : List Area
    , area : Maybe Area
    , days : List DayEntry
    , day : Maybe String
    , board : Maybe Board
    , hours : List String
    , selection : Selection
    , selected : Maybe String
    , here : Maybe Point
    , layer : Layer
    , showBeaches : Bool
    , showTrails : Bool
    , panel : Panel
    , trailSelected : Maybe Int
    , trailsFile : TrailsFile
    , waterFile : WaterFileState
    , loreOpen : Bool
    , blurbOpen : Bool
    , sosOpen : Bool
    , playlistOpen : Bool
    , playerOffset : ( Int, Int )
    , playerDrag : Maybe { x : Int, y : Int }
    , map : MapState
    , status : Status
    , zoomedOut : Bool
    , fitted : Bool
    , reducedMotion : Bool
    , embed : Bool
    }


{-| The trails to draw: the area's file, else the board's own.
-}
trails : Model -> Maybe Trails
trails model =
    case ( model.trailsFile, model.area, model.board ) of
        ( TrailsLoaded found, _, _ ) ->
            Just found

        ( TrailsMissing, Just area, Just board ) ->
            Just (Trails.fromBoard area.id board.trails)

        _ ->
            Nothing


initial : Locale -> String -> Query -> Bool -> Model
initial loc path query reducedMotion =
    { loc = loc
    , catalogsPending = List.length Language.all
    , path = path
    , query = query
    , areas = []
    , area = Nothing
    , days = []
    , day = Nothing
    , board = Nothing
    , hours = []
    , selection = Beach.BestHour
    , selected = Nothing
    , here = Nothing
    , layer = Layer.Off
    , showBeaches = True
    , showTrails = True
    , panel = Closed
    , trailSelected = Nothing
    , trailsFile = TrailsPending
    , waterFile = WaterFilePending
    , loreOpen = False
    , blurbOpen = False
    , sosOpen = False
    , playlistOpen = False
    , playerOffset = ( 0, 0 )
    , playerDrag = Nothing
    , map = MapNone
    , status = Idle
    , zoomedOut = False
    , fitted = False
    , reducedMotion = reducedMotion
    , embed = False
    }


beaches : Model -> List Beach
beaches model =
    case model.board of
        Just board ->
            List.map (withFileWater model) board.beaches

        Nothing ->
            []


{-| A board with no water for a beach (the app has no provider for the area, or its name match
missed) takes the area's own file for that beach: the card and the marker's band then say what the
agency says, as they do in the areas the app serves. The board's own points always win.
-}
withFileWater : Model -> Beach -> Beach
withFileWater model beach =
    case ( beach.water.points, model.waterFile ) of
        ( [], WaterFileLoaded file ) ->
            case filePoints beach file.points of
                [] ->
                    beach

                found ->
                    { beach | water = waterFrom file.source file.sampledOn found }

        _ ->
            beach


{-| The file's points at this beach: by name first (the agency names the beach), then by place,
within about a kilometre. A point the agency shares between two beaches stays on both; the map
draws it once.
-}
filePoints : Beach -> List WaterPoint -> List WaterPoint
filePoints beach points =
    let
        byName =
            List.filter (\p -> nameMatches beach.name p.location) points
    in
    if List.isEmpty byName then
        List.filter (nearBeach beach) points

    else
        byName


nameMatches : String -> String -> Bool
nameMatches beach location =
    let
        b =
            String.toLower beach

        l =
            String.toLower location
    in
    String.length b > 2 && (String.contains b l || String.contains l b)


nearBeach : Beach -> WaterPoint -> Bool
nearBeach beach p =
    abs (beach.lat - p.lat) < 0.01 && abs (beach.lon - p.lon) < 0.01


{-| The board's summary shape, so `Water.summaryText` reads it in every language: `PRÓPRIA (1/1 pts,
9 Feb)`, `IMPRÓPRIA (1/1 pts, 9 Feb)` or `0/2 PRÓPRIA — avoid MR01 (9 Feb)`.
-}
waterFrom : String -> String -> List WaterPoint -> Water
waterFrom source sampledOn points =
    let
        proper =
            List.filter (\p -> p.condition == Proper) points |> List.length

        improper =
            List.filter (\p -> p.condition == Improper) points |> List.length

        total =
            List.length points

        unknown =
            total - proper - improper

        when =
            dayMonth sampledOn

        summary =
            if total == 0 then
                "no data"

            else if improper == total then
                "IMPRÓPRIA (" ++ String.fromInt total ++ "/" ++ String.fromInt total ++ " pts, " ++ when ++ ")"

            else if improper > 0 then
                String.fromInt proper
                    ++ "/"
                    ++ String.fromInt total
                    ++ " PRÓPRIA — avoid "
                    ++ (List.filter (\p -> p.condition == Improper) points |> List.map .point |> String.join ", ")
                    ++ " ("
                    ++ when
                    ++ ")"

            else if unknown == total then
                "no verdict (" ++ String.fromInt total ++ " pts unknown, " ++ when ++ ")"

            else if unknown > 0 then
                "PRÓPRIA (" ++ String.fromInt proper ++ "/" ++ String.fromInt total ++ " pts, " ++ String.fromInt unknown ++ " unknown, " ++ when ++ ")"

            else
                "PRÓPRIA (" ++ String.fromInt proper ++ "/" ++ String.fromInt total ++ " pts, " ++ when ++ ")"
    in
    { summary = summary
    , unfit = improper > 0
    , note = Nothing
    , source = Just source
    , points = points
    }


{-| `2026-02-09` as the app writes it in a summary: `9 Feb`.
-}
dayMonth : String -> String
dayMonth date =
    case String.split "-" date of
        [ _, month, day ] ->
            String.fromInt (Maybe.withDefault 0 (String.toInt day))
                ++ " "
                ++ (case month of
                        "01" ->
                            "Jan"

                        "02" ->
                            "Feb"

                        "03" ->
                            "Mar"

                        "04" ->
                            "Apr"

                        "05" ->
                            "May"

                        "06" ->
                            "Jun"

                        "07" ->
                            "Jul"

                        "08" ->
                            "Aug"

                        "09" ->
                            "Sep"

                        "10" ->
                            "Oct"

                        "11" ->
                            "Nov"

                        "12" ->
                            "Dec"

                        _ ->
                            month
                   )

        _ ->
            date


{-| The file's points the board does not already draw. They belong to no beach, so only the water
layer shows them.
-}
lagoonWater : Model -> List WaterPoint
lagoonWater model =
    case model.waterFile of
        WaterFileLoaded file ->
            let
                drawn =
                    List.concatMap (.water >> .points) (beaches model)
            in
            List.filter (\p -> not (List.any (WaterFile.same p) drawn)) file.points

        _ ->
            []
