module Update exposing (Env, describe, init, update)

{-| The page's one state machine: a message and a model in, a model and a list of effects out.
Nothing here touches the browser, so every path is a test.
-}

import Area exposing (Area)
import Beach exposing (Beach, Selection(..))
import Board exposing (Board)
import Config
import Dict exposing (Dict)
import Effect exposing (Camera(..), Effect(..))
import FlowData
import Geo exposing (Point)
import I18n
import Language exposing (Language)
import Layer exposing (Layer)
import MapView
import Model exposing (DayEntry, MapState(..), Model, Panel(..), Status(..), TrailsFile(..))
import Msg exposing (FetchError(..), Fold(..), Loaded(..), Msg(..))
import Params exposing (Query)
import Parse
import TrailGeo
import Trails exposing (Route, Trails)


{-| What the page reads from the browser before it starts.
-}
type alias Env =
    { path : String
    , query : Query
    , languages : List String
    , storedLanguage : Maybe String
    , reducedMotion : Bool
    }



-- What every part shares: the query string, the effects that bring the map up to date, and the
-- way a failed request reads in the footer.


active : Model -> Bool
active model =
    model.map == MapLoading || model.map == MapReady


setParam : Model -> String -> String -> Model
setParam model key value =
    { model | query = Params.set model.query key value }


deleteParam : Model -> String -> Model
deleteParam model key =
    { model | query = Params.delete model.query key }


url : Model -> Effect
url model =
    ReplaceUrl model.path (Params.toString model.query)


{-| The markers, raster and visibility, when there is a map to hold them.
-}
sync : Model -> List Effect -> ( Model, List Effect )
sync model more =
    if active model then
        ( model, SyncMap (MapView.syncJson model) :: more )

    else
        ( model, more )


trailEffects : Model -> List Effect
trailEffects model =
    if active model then
        [ SetTrails (TrailGeo.collection (Model.trails model) model.loc) ]

    else
        []


flowEffects : Model -> List Effect
flowEffects model =
    if active model then
        [ SetFlow (FlowData.json model) ]

    else
        []


currentArea : Model -> Maybe String
currentArea model =
    Maybe.map .id model.area


{-| The answer to a request for an area the visitor has left is not theirs any more.
-}
guardArea : Model -> String -> (() -> ( Model, List Effect )) -> ( Model, List Effect )
guardArea model area next =
    if currentArea model == Just area then
        next ()

    else
        ( model, [] )


guardDay : Model -> String -> String -> (() -> ( Model, List Effect )) -> ( Model, List Effect )
guardDay model area day next =
    if currentArea model == Just area && model.day == Just day then
        next ()

    else
        ( model, [] )


{-| What the footer says of a failed request: the status and the path, as the old page's
`fetchJson` did. The flag is true for a missing file.
-}
describe : FetchError -> String -> ( String, Bool )
describe error path =
    case error of
        HttpError status ->
            ( String.fromInt status ++ " " ++ path, status == 404 )

        NetworkError ->
            ( "network error " ++ path, False )

        BadUrl ->
            ( "bad address " ++ path, False )

        BadData _ ->
            ( "bad data " ++ path, False )


fail : Model -> FetchError -> String -> ( Model, List Effect )
fail model error path =
    let
        ( text, missing ) =
            describe error path
    in
    ( { model | status = Failed text missing }, [] )



-- Data arriving, and the choice of an area or a day that starts a load.


catalogLoaded : Model -> Language -> Result FetchError (Dict String String) -> ( Model, List Effect )
catalogLoaded model language result =
    let
        loc =
            model.loc

        catalog =
            case result of
                Ok messages ->
                    Dict.insert (Language.tag language) messages loc.catalog

                Err _ ->
                    loc.catalog

        pending =
            model.catalogsPending - 1

        next0 =
            { model | loc = { loc | catalog = catalog }, catalogsPending = pending }

        next =
            case result of
                Err e ->
                    { next0 | status = Failed (Tuple.first (describe e ("i18n/" ++ Language.tag language ++ ".json"))) False }

                Ok _ ->
                    next0
    in
    if pending == 0 then
        ( next, [ SetDocument (Language.tag model.loc.language) (I18n.t next.loc "title.map" []), FetchAreas ] )

    else
        ( next, [] )


selectArea : Model -> Area -> ( Model, List Effect )
selectArea model area =
    let
        firstMap =
            model.map == MapNone

        next =
            setParam
                { model
                    | area = Just area
                    , status = Loading area.name
                    , trailsFile = TrailsPending
                    , trailSelected = Nothing
                    , map =
                        if firstMap then
                            MapLoading

                        else
                            model.map
                }
                "area"
                area.id

        mapEffect =
            if firstMap then
                InitMap area.lon area.lat

            else
                MoveCamera (Jump area.lon area.lat Config.areaZoom)
    in
    ( next, [ url next, mapEffect, FetchLatest area.id, FetchTrails area.id ] )


areasLoaded : Model -> List Area -> ( Model, List Effect )
areasLoaded model areas =
    let
        wanted =
            Params.get model.query "area"

        chosen =
            case List.filter (\a -> Just a.id == wanted) areas of
                area :: _ ->
                    Just area

                [] ->
                    List.head areas
    in
    case chosen of
        Nothing ->
            ( { model | areas = areas, status = NoAreas }, [] )

        Just area ->
            selectArea { model | areas = areas } area


areaPicked : Model -> String -> ( Model, List Effect )
areaPicked model id =
    case List.filter (\a -> a.id == id) model.areas of
        [] ->
            ( model, [] )

        area :: _ ->
            let
                -- A new area starts afresh: no beach picked, the map fits its beaches.
                reset =
                    deleteParam (deleteParam { model | fitted = False, selected = Nothing, board = Nothing, day = Nothing } "beach") "day"

                ( next, effects ) =
                    selectArea reset area
            in
            ( next, effects ++ Tuple.second (sync next []) )


selectDay : Model -> DayEntry -> ( Model, List Effect )
selectDay model day =
    let
        next =
            setParam { model | day = Just day.date, status = Loading day.date } "day" day.date
    in
    ( next, [ url next, FetchBoard (Maybe.withDefault "" (currentArea model)) day.date day.file ] )


last : List a -> Maybe a
last xs =
    List.head (List.reverse xs)


latestLoaded : Model -> String -> List DayEntry -> ( Model, List Effect )
latestLoaded model area days =
    guardArea model area <|
        \() ->
            let
                wanted =
                    Params.get model.query "day"

                byParam =
                    List.filter (\d -> Just d.date == wanted) days |> List.head
            in
            case
                case byParam of
                    Just d ->
                        Just d

                    Nothing ->
                        last days
            of
                Nothing ->
                    ( { model | days = days, status = Failed ("no days " ++ area) False }, [] )

                Just day ->
                    selectDay { model | days = days } day


dayPicked : Model -> String -> ( Model, List Effect )
dayPicked model day =
    case List.filter (\d -> d.date == day) model.days of
        found :: _ ->
            selectDay model found

        [] ->
            ( model, [] )


{-| The first board of an area fits the map to its beaches; a layer that zoomed the map out keeps
its view.
-}
fit : Model -> ( Bool, List Effect )
fit model =
    case model.board of
        Just board ->
            if not (model.fitted || model.zoomedOut || not (active model)) then
                case MapView.beachBounds board of
                    Just ( ( w, s ), ( e, n ) ) ->
                        ( True, [ MoveCamera (Fit w s e n 40 13 True) ] )

                    Nothing ->
                        ( False, [] )

            else
                ( model.fitted, [] )

        Nothing ->
            ( model.fitted, [] )


showBoard : Model -> Board -> ( Model, List Effect )
showBoard model board =
    let
        fromUrl =
            case ( Params.get model.query "beach", model.selected ) of
                ( Just name, Nothing ) ->
                    if List.any (\b -> b.name == name) board.beaches then
                        Just name

                    else
                        Nothing

                ( _, selected ) ->
                    selected

        next0 =
            { model | board = Just board, hours = Board.hours board, selection = BestHour, selected = fromUrl, status = Idle }

        ( fitted, fitEffects ) =
            fit next0

        next =
            { next0 | fitted = fitted }
    in
    sync next (fitEffects ++ trailEffects next ++ flowEffects next)


boardLoaded : Model -> String -> String -> Result FetchError Loaded -> ( Model, List Effect )
boardLoaded model area file result =
    case result of
        Err e ->
            fail model e ("data/" ++ area ++ "/" ++ file)

        Ok (Newer schema) ->
            ( { model | status = TooNew schema }, [] )

        Ok (Read board) ->
            showBoard model board


trailsLoaded : Model -> Result FetchError Trails -> ( Model, List Effect )
trailsLoaded model result =
    let
        next =
            case result of
                Ok found ->
                    { model | trailsFile = TrailsLoaded found }

                Err _ ->
                    { model | trailsFile = TrailsMissing }
    in
    ( next, trailEffects next )



-- The visitor: the slider, the picked beach, the layers, the panels, the language and the map's
-- own events.


hourMoved : Model -> Int -> ( Model, List Effect )
hourMoved model index =
    let
        picked =
            if index >= 0 then
                List.drop index model.hours |> List.head

            else
                Nothing

        next =
            { model
                | selection =
                    case picked of
                        Just h ->
                            At h

                        Nothing ->
                            BestHour
            }
    in
    sync next (flowEffects next)


findBeach : Model -> String -> Maybe Beach
findBeach model name =
    Model.beaches model |> List.filter (\b -> b.name == name) |> List.head


beachPicked : Model -> String -> Bool -> ( Model, List Effect )
beachPicked model name pan =
    let
        next =
            setParam { model | selected = Just name, trailSelected = Nothing } "beach" name

        camera =
            case ( pan, active next, findBeach next name ) of
                ( True, True, Just b ) ->
                    [ MoveCamera (Pan b.lon b.lat) ]

                _ ->
                    []
    in
    sync next (url next :: camera)


{-| The card of a beach or of a trail closes; a click on the empty map does the same.
-}
closeCards : Model -> ( Model, List Effect )
closeCards model =
    if model.selected == Nothing && model.trailSelected == Nothing then
        ( model, [] )

    else
        let
            next =
                deleteParam { model | selected = Nothing, trailSelected = Nothing } "beach"
        in
        sync next [ url next ]


{-| El Nino needs the Pacific in view, below the area's own minimum zoom.
-}
zoomForLayer : Model -> ( Model, List Effect )
zoomForLayer model =
    let
        nino =
            model.layer == Layer.Elnino
    in
    if nino == model.zoomedOut then
        ( model, [] )

    else
        let
            next =
                { model | zoomedOut = nino }

            minZoom =
                MoveCamera
                    (MinZoom
                        (if nino then
                            0

                         else
                            Config.areaMinZoom
                        )
                    )

            view =
                case ( nino, Maybe.andThen MapView.beachBounds next.board ) of
                    ( True, _ ) ->
                        [ MoveCamera (Pacific next.reducedMotion) ]

                    ( False, Just ( ( w, s ), ( e, n ) ) ) ->
                        [ MoveCamera (Fit w s e n 40 13 next.reducedMotion) ]

                    ( False, Nothing ) ->
                        []
        in
        ( next, minZoom :: view )


layerPressed : Model -> Layer -> ( Model, List Effect )
layerPressed model layer =
    if not (Layer.enabled layer) then
        ( model, [] )

    else
        let
            -- A pressed layer button turns its layer off again.
            picked =
                if layer == model.layer then
                    Layer.Off

                else
                    layer

            ( next, camera ) =
                zoomForLayer (setParam { model | layer = picked } "layer" (Layer.key picked))
        in
        sync next (camera ++ flowEffects next ++ [ url next ])


toggled : Model -> String -> Bool -> ( Model, List Effect )
toggled model key on =
    let
        flag =
            if on then
                "1"

            else
                "0"

        next0 =
            if key == "beaches" then
                { model | showBeaches = on }

            else
                { model | showTrails = on }

        next =
            setParam next0 key flag
    in
    sync next [ url next ]


panelToggled : Model -> Panel -> ( Model, List Effect )
panelToggled model panel =
    ( { model
        | panel =
            if model.panel == panel then
                Closed

            else
                panel
      }
    , []
    )


routeBounds : Route -> Maybe ( ( Float, Float ), ( Float, Float ) )
routeBounds route =
    case List.concat (Trails.drawableLines route) of
        [] ->
            Nothing

        first :: rest ->
            rest
                |> List.foldl (\p ( ( w, s ), ( e, n ) ) -> ( ( min w p.lon, min s p.lat ), ( max e p.lon, max n p.lat ) ))
                    ( ( first.lon, first.lat ), ( first.lon, first.lat ) )
                |> Just


trailChosen : Model -> Int -> Bool -> ( Model, List Effect )
trailChosen model id fitIt =
    case Model.trails model |> Maybe.andThen (\t -> Trails.routeAt t id) of
        Just route ->
            let
                next =
                    deleteParam { model | trailSelected = Just id, selected = Nothing } "beach"

                camera =
                    case ( fitIt, active next, routeBounds route ) of
                        ( True, True, Just ( ( w, s ), ( e, n ) ) ) ->
                            [ MoveCamera (Fit w s e n 60 15 next.reducedMotion) ]

                        _ ->
                            []
            in
            sync next (url next :: camera)

        Nothing ->
            ( model, [] )


nearPressed : Model -> ( Model, List Effect )
nearPressed model =
    case model.here of
        Just _ ->
            sync { model | here = Nothing } []

        Nothing ->
            ( model, [ Locate ] )


foldToggled : Model -> Fold -> Model
foldToggled model fold =
    case fold of
        LoreFold ->
            { model | loreOpen = not model.loreOpen }

        BlurbFold ->
            { model | blurbOpen = not model.blurbOpen }


sosClosed : Model -> ( Model, List Effect )
sosClosed model =
    if model.sosOpen then
        ( { model | sosOpen = False }, [ Focus "sos" ] )

    else
        ( model, [] )


languagePicked : Model -> Language -> ( Model, List Effect )
languagePicked model language =
    if language == model.loc.language then
        ( model, [] )

    else
        let
            loc =
                model.loc

            ( next, effects ) =
                let
                    m =
                        setParam { model | loc = { loc | language = language } } "lang" (Language.tag language)
                in
                sync m (trailEffects m)
        in
        ( next
        , [ StoreLanguage language, url next, SetDocument (Language.tag language) (I18n.t next.loc "title.map" []) ]
            ++ effects
        )


mapEvent : Model -> String -> String -> ( Model, List Effect )
mapEvent model kind arg =
    case kind of
        "ready" ->
            ( { model | map = MapReady }, [] )

        "error" ->
            -- An error before the map loads is the style or its sprites: the list carries the
            -- page, and says why there is no map.
            if model.map == MapLoading then
                ( { model | map = MapFailed "map.failed", panel = BeachList }, [] )

            else
                ( model, [] )

        "click" ->
            closeCards model

        "beach" ->
            beachPicked model arg False

        "trail" ->
            case Parse.tryInt arg of
                Just id ->
                    trailChosen model id False

                Nothing ->
                    ( model, [] )

        _ ->
            ( model, [] )



-- The entry points.


init : Env -> ( Model, List Effect )
init env =
    let
        language =
            Language.resolve (Params.get env.query "lang") env.storedLanguage env.languages Language.all

        base =
            Model.initial { catalog = Dict.empty, language = language } env.path env.query env.reducedMotion

        layer =
            Params.get env.query "layer"
                |> Maybe.andThen Layer.ofKey
                |> Maybe.andThen
                    (\l ->
                        if Layer.enabled l then
                            Just l

                        else
                            Nothing
                    )
                |> Maybe.withDefault Layer.Off
    in
    ( { base
        | layer = layer
        , showBeaches = Params.get env.query "beaches" /= Just "0"
        , showTrails = Params.get env.query "trails" /= Just "0"
        , zoomedOut = layer == Layer.Elnino
      }
    , List.map FetchCatalog Language.all
    )


update : Msg -> Model -> ( Model, List Effect )
update message model =
    case message of
        CatalogLoaded language result ->
            catalogLoaded model language result

        AreasLoaded (Ok areas) ->
            areasLoaded model areas

        AreasLoaded (Err e) ->
            fail model e "data/areas.json"

        LatestLoaded area (Ok days) ->
            latestLoaded model area days

        LatestLoaded area (Err e) ->
            guardArea model area (\() -> fail model e ("data/" ++ area ++ "/latest.json"))

        BoardLoaded area day file result ->
            guardDay model area day (\() -> boardLoaded model area file result)

        TrailsFileLoaded area result ->
            guardArea model area (\() -> trailsLoaded model result)

        AreaPicked id ->
            areaPicked model id

        DayPicked day ->
            dayPicked model day

        HourMoved index ->
            hourMoved model index

        BeachPicked name pan ->
            beachPicked model name pan

        CardClosed ->
            closeCards model

        LayerPressed layer ->
            layerPressed model layer

        BeachesToggled ->
            toggled model "beaches" (not model.showBeaches)

        TrailsToggled ->
            toggled model "trails" (not model.showTrails)

        ListToggled ->
            panelToggled model BeachList

        TrailPanelToggled ->
            panelToggled model TrailList

        TrailChosen id fitIt ->
            trailChosen model id fitIt

        NearPressed ->
            nearPressed model

        Located (Ok point) ->
            sync { model | here = Just point, panel = BeachList } []

        Located (Err _) ->
            ( model, [ Alert (I18n.t model.loc "near.denied" []) ] )

        FoldToggled fold ->
            ( foldToggled model fold, [] )

        SosToggled ->
            ( { model | sosOpen = not model.sosOpen }, [] )

        SosClosed ->
            sosClosed model

        LanguagePicked language ->
            languagePicked model language

        PlaylistPressed ->
            ( { model | playlistOpen = not model.playlistOpen }, [] )

        MapEvent kind arg ->
            mapEvent model kind arg

        Ignored ->
            ( model, [] )
