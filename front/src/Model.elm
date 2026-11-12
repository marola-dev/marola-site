module Model exposing (DayEntry, MapState(..), Model, Panel(..), Status(..), TrailsFile(..), beaches, initial, trails)

import Area exposing (Area)
import Beach exposing (Beach, Selection)
import Board exposing (Board)
import Geo exposing (Point)
import I18n exposing (Locale)
import Layer exposing (Layer)
import Params exposing (Query)
import Trails exposing (Trails)


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
    , loreOpen : Bool
    , blurbOpen : Bool
    , sosOpen : Bool
    , playlistOpen : Bool
    , map : MapState
    , status : Status
    , zoomedOut : Bool
    , fitted : Bool
    , reducedMotion : Bool
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
    , catalogsPending = 2
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
    , loreOpen = False
    , blurbOpen = False
    , sosOpen = False
    , playlistOpen = False
    , map = MapNone
    , status = Idle
    , zoomedOut = False
    , fitted = False
    , reducedMotion = reducedMotion
    }


beaches : Model -> List Beach
beaches model =
    case model.board of
        Just board ->
            board.beaches

        Nothing ->
            []
