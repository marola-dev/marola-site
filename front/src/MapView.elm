module MapView exposing (beachBounds, drop, syncJson, waterPoints, waveIcon)

{-| What the map shows, as one JSON text for `maplibre_ffi.mjs`: the beach dots, the water-sampling
points, the visitor, the satellite layer and the trail visibility. The map keeps the last text of
each part and redraws only the part that changed.
-}

import Area
import Aspects
import AspectsView
import Band
import Beach exposing (Beach)
import Board exposing (Board)
import I18n
import Json.Encode as E
import Layer
import Model exposing (Model)
import Raster
import Tree exposing (Tree)
import Water exposing (WaterPoint)
import WaterFile


{-| The west, south, east and north edges of the beaches, or none.
-}
beachBounds : Board -> Maybe ( ( Float, Float ), ( Float, Float ) )
beachBounds board =
    case board.beaches of
        [] ->
            Nothing

        first :: rest ->
            rest
                |> List.foldl (\b ( ( w, s ), ( e, n ) ) -> ( ( min w b.lon, min s b.lat ), ( max e b.lon, max n b.lat ) ))
                    ( ( first.lon, first.lat ), ( first.lon, first.lat ) )
                |> Just


type alias Marker =
    { key : String
    , lon : Float
    , lat : Float
    , label : Maybe String
    , node : Tree
    , tip : Tree
    , tipClass : String
    , tipAnchor : String
    , offset : Int
    , click : Maybe String
    }


nullable : (a -> E.Value) -> Maybe a -> E.Value
nullable f value =
    Maybe.map f value |> Maybe.withDefault E.null


markerJson : Marker -> E.Value
markerJson m =
    E.object
        [ ( "key", E.string m.key )
        , ( "lon", E.float m.lon )
        , ( "lat", E.float m.lat )
        , ( "label", nullable E.string m.label )
        , ( "node", Tree.toJson m.node )
        , ( "tip", Tree.toJson m.tip )
        , ( "tip_class", E.string m.tipClass )
        , ( "tip_anchor", E.string m.tipAnchor )
        , ( "offset", E.int m.offset )
        , ( "click", nullable E.string m.click )
        ]


num : Float -> String
num =
    String.fromFloat


{-| A beach is a dot in its score colour: a white ring keeps neighbours apart where beaches crowd,
and the picked one grows into a badge with its number. The colour is a class, never an inline
style: the CSP blocks `style=`.
-}
waveIcon : String -> Bool -> Maybe Int -> Tree
waveIcon bandClass selected score =
    let
        size =
            if selected then
                32

            else
                16

        r =
            size / 2

        label =
            case ( selected, score ) of
                ( True, Just s ) ->
                    [ Tree.svg "text"
                        [ ( "x", "16" )
                        , ( "y", "20.5" )
                        , ( "text-anchor", "middle" )
                        , ( "font-size", "13" )
                        , ( "font-weight", "600" )
                        , ( "class"
                          , if bandClass == "c40" then
                                "num dark"

                            else
                                "num"
                          )
                        ]
                        [ Tree.text (String.fromInt s) ]
                    ]

                _ ->
                    []
    in
    Tree.svg "svg"
        [ ( "viewBox", "0 0 " ++ num size ++ " " ++ num size )
        , ( "width", num size )
        , ( "height", num size )
        , ( "aria-hidden", "true" )
        ]
        ([ Tree.svg "circle" [ ( "cx", num r ), ( "cy", num r ), ( "r", num (r - 0.5) ), ( "fill", "#1d2733" ) ] []
         , Tree.svg "circle"
            [ ( "cx", num r )
            , ( "cy", num r )
            , ( "r", num (r - 2) )
            , ( "class", "dot f-" ++ bandClass )
            , ( "stroke", "#fff" )
            , ( "stroke-width", "2" )
            ]
            []
         ]
            ++ label
        )


beachMarker : Model -> Beach -> Marker
beachMarker model b =
    let
        shown =
            Beach.shown b model.selection

        score =
            Maybe.map .score shown

        selected =
            model.selected == Just b.name

        past =
            case ( shown, model.board ) of
                ( Just s, Just board ) ->
                    Board.isPast board s.h

                _ ->
                    False

        cls =
            "wave"
                ++ (if selected then
                        " selected"

                    else
                        ""
                   )
                ++ (if past then
                        " past"

                    else
                        ""
                   )

        bandClass =
            Band.cssClass (Band.ofScore score b.water.unfit)
    in
    { key = b.name
    , lon = b.lon
    , lat = b.lat
    , label = Just b.name
    , node = Tree.el "div" [ ( "class", cls ) ] [ waveIcon bandClass selected score ]
    , tip = Tree.el "div" [] (AspectsView.children (Aspects.ofBeach b shown model.loc))
    , tipClass = "aspects"
    , tipAnchor = ""
    , offset =
        if selected then
            18

        else
            10
    , click = Just "beach"
    }


{-| Lucide's droplet, so a sampling point never reads as a beach dot; `style.css` fills it by band.
-}
drop : Tree
drop =
    let
        d =
            "M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z"
    in
    Tree.svg "svg"
        [ ( "viewBox", "0 0 24 24" ), ( "aria-hidden", "true" ), ( "focusable", "false" ) ]
        [ Tree.svg "path" [ ( "class", "rim" ), ( "d", d ) ] []
        , Tree.svg "path" [ ( "class", "fill" ), ( "d", d ) ] []
        ]


waterMarker : Model -> WaterPoint -> Marker
waterMarker model p =
    let
        text =
            p.point ++ " (" ++ p.location ++ "): " ++ Water.conditionLabel p.condition model.loc ++ ", " ++ Water.sampledText p model.loc
    in
    { key = p.point
    , lon = p.lon
    , lat = p.lat
    , label = Just p.point
    , node = Tree.el "div" [ ( "class", "wpoint " ++ Band.cssClass (Water.conditionBand p.condition) ) ] [ drop ]
    , tip = Tree.el "span" [ ( "class", "water" ) ] [ Tree.text text ]
    , tipClass = ""
    , tipAnchor = ""
    , offset = 8
    , click = Nothing
    }


{-| The area's pins: the partner's place and the named islands. Every label is in the page
language; the area's camera enters the first and the beaches' bounds do not pull it away
(`Update.pinned`).
-}
pinMarker : Model -> List Marker
pinMarker model =
    List.indexedMap (pinMarkerAt model) (List.filter (visiblePin model) (areaPins model))


{-| A place pin is always on the map; a diving site belongs to the scuba layer. An area with
dive sites shows only those on the scuba layer; an area without them keeps its place pins, so the
layer never empties a map that has nothing to put in its place.
-}
visiblePin : Model -> Area.Pin -> Bool
visiblePin model pin =
    let
        hasDives =
            List.any Area.isDive (areaPins model)
    in
    if model.scuba && hasDives then
        Area.isDive pin

    else
        not (Area.isDive pin)


areaPins : Model -> List Area.Pin
areaPins model =
    case model.area of
        Just area ->
            (case area.pin of
                Just pin ->
                    [ pin ]

                Nothing ->
                    []
            )
                ++ area.pins

        Nothing ->
            []


pinMarkerAt : Model -> Int -> Area.Pin -> Marker
pinMarkerAt model index pin =
    if Area.isDive pin then
        diveMarker model index pin

    else if Area.isPeak pin then
        peakMarker model index pin

    else
        placeMarker model index pin


{-| The visible label names it; the hover bubble describes it, so the two never read the same.
-}
pinTip : Model -> Area.Pin -> Tree
pinTip model pin =
    case Area.pinDescription model.loc pin of
        Just description ->
            Tree.el "span"
                [ ( "class", "pin-tip" ) ]
                [ Tree.text
                    (if Area.isPeak pin then
                        Area.pinLabel model.loc pin ++ " — " ++ description

                     else
                        description
                    )
                ]

        Nothing ->
            Tree.el "span" [] []


placeMarker : Model -> Int -> Area.Pin -> Marker
placeMarker model index pin =
    let
        label =
            Area.pinLabel model.loc pin

        -- The partner's place is a link when the area names a URL: a visitor who wants to know who
        -- keeps the map gets there in one click. A new tab, so an embed stays put.
        link =
            case pin.url of
                Just url ->
                    [ ( "href", url ), ( "target", "_blank" ), ( "rel", "noopener" ) ]

                Nothing ->
                    []
    in
    { key = "pin-" ++ String.fromInt index ++ "-" ++ pin.name
    , lon = pin.lon
    , lat = pin.lat
    , label = Just label
    , node =
        Tree.el
            (if List.isEmpty link then
                "div"

             else
                "a"
            )
            (( "class"
             , if pin.labelBelow then
                "pin label-below"

               else
                "pin"
             )
                :: ( "aria-label", label )
                :: link
            )
            [ Tree.el "span" [ ( "class", "pin-label" ) ] [ Tree.text label ]
            , Tree.el "span" [ ( "class", "pin-dot" ) ] []
            ]
    , tip = pinTip model pin
    , tipClass = ""
    , tipAnchor = "top"
    , offset = 10
    , click = Nothing
    }


{-| A diving site: a round mask marker, drawn only on the scuba layer.
-}
diveMarker : Model -> Int -> Area.Pin -> Marker
diveMarker model index pin =
    let
        label =
            Area.pinLabel model.loc pin
    in
    { key = "dive-" ++ String.fromInt index ++ "-" ++ pin.name
    , lon = pin.lon
    , lat = pin.lat
    , label = Just label
    , node =
        Tree.el "div"
            [ ( "class", "dive" ), ( "role", "img" ), ( "aria-label", label ) ]
            [ diveIcon, Tree.el "span" [ ( "class", "pin-label" ) ] [ Tree.text label ] ]
    , tip = pinTip model pin
    , tipClass = ""
    , tipAnchor = "top"
    , offset = 14
    , click = Nothing
    }


{-| A scuba mask: two lenses, a strap and a regulator, on the accent dot.
-}
diveIcon : Tree
diveIcon =
    Tree.svg "svg"
        [ ( "viewBox", "0 0 24 24" ), ( "aria-hidden", "true" ), ( "focusable", "false" ) ]
        [ Tree.svg "circle" [ ( "class", "rim" ), ( "cx", "12" ), ( "cy", "12" ), ( "r", "11" ) ] []
        , Tree.svg "circle" [ ( "class", "fill" ), ( "cx", "12" ), ( "cy", "12" ), ( "r", "9" ) ] []
        , Tree.svg "path"
            [ ( "class", "mask" )
            , ( "d", "M4.5 8.5h15a1 1 0 0 1 1 1v3.5a2 2 0 0 1-2 2h-3.5L12 17l-3-2H5.5a2 2 0 0 1-2-2V9.5a1 1 0 0 1 1-1Z" )
            ]
            []
        , Tree.svg "circle" [ ( "class", "lens" ), ( "cx", "9" ), ( "cy", "11.5" ), ( "r", "1.5" ) ] []
        , Tree.svg "circle" [ ( "class", "lens" ), ( "cx", "15" ), ( "cy", "11.5" ), ( "r", "1.5" ) ] []
        ]


{-| A peak: a round mountain marker with no permanent label; the name is in its tooltip.
-}
peakMarker : Model -> Int -> Area.Pin -> Marker
peakMarker model index pin =
    let
        label =
            Area.pinLabel model.loc pin
    in
    { key = "peak-" ++ String.fromInt index ++ "-" ++ pin.name
    , lon = pin.lon
    , lat = pin.lat
    , label = Just label
    , node =
        Tree.el "div"
            [ ( "class", "peak peak-" ++ String.fromInt (modBy 3 index) ), ( "role", "img" ), ( "aria-label", label ) ]
            [ peakIcon ]
    , tip = pinTip model pin
    , tipClass = ""
    , tipAnchor = "top"
    , offset = 14
    , click = Nothing
    }


peakIcon : Tree
peakIcon =
    Tree.svg "svg"
        [ ( "viewBox", "0 0 24 24" ), ( "aria-hidden", "true" ), ( "focusable", "false" ) ]
        [ Tree.svg "circle" [ ( "class", "rim" ), ( "cx", "12" ), ( "cy", "12" ), ( "r", "11" ) ] []
        , Tree.svg "circle" [ ( "class", "fill" ), ( "cx", "12" ), ( "cy", "12" ), ( "r", "9" ) ] []
        , Tree.svg "path"
            [ ( "class", "peak-shape" )
            , ( "d", "M4 18.5 10 7l3.2 5.8 1.6-2.6 5.2 8.3H4Z" )
            ]
            []
        ]


selectedBeach : Model -> Maybe Beach
selectedBeach model =
    model.selected
        |> Maybe.andThen (\name -> Model.beaches model |> List.filter (\b -> b.name == name) |> List.head)


{-| The water layer shows every beach's sampling points; the others only the selected beach's.

An area whose board has no beaches at all (the Complexo Lagunar while the app's Overpass query
times out, marola-app#60) would otherwise open on an empty map: the file's points are the only
data it has, so they are drawn whatever the layer.

-}
waterPoints : Model -> List WaterPoint
waterPoints model =
    let
        shown =
            case ( model.layer, selectedBeach model ) of
                ( Layer.Water, _ ) ->
                    Model.beaches model

                ( _, Just b ) ->
                    [ b ]

                ( _, Nothing ) ->
                    []
    in
    List.concatMap (.water >> .points) shown
        ++ (if model.layer == Layer.Water || List.isEmpty (Model.beaches model) then
                Model.lagoonWater model

            else
                []
           )
        |> distinct


{-| A sample is drawn once: the board may carry the same agency point on two beaches, and the
file adds the points the board leaves out.
-}
distinct : List WaterPoint -> List WaterPoint
distinct points =
    List.foldl
        (\p kept ->
            if List.any (WaterFile.same p) kept then
                kept

            else
                kept ++ [ p ]
        )
        []
        points


hereMarker : Model -> List Marker
hereMarker model =
    case model.here of
        Nothing ->
            []

        Just p ->
            [ { key = "here"
              , lon = p.lon
              , lat = p.lat
              , label = Nothing
              , node = Tree.el "div" [ ( "class", "here" ) ] []
              , tip = Tree.el "span" [] [ Tree.text (I18n.t model.loc "near.you" []) ]
              , tipClass = ""
              , tipAnchor = ""
              , offset = 8
              , click = Nothing
              }
            ]


rasterJson : Model -> E.Value
rasterJson model =
    case ( Raster.ofLayer model.layer, model.board ) of
        ( Just r, Just board ) ->
            Raster.spec r board.today

        _ ->
            E.null


ninoJson : Model -> E.Value
ninoJson model =
    case model.layer of
        Layer.Elnino ->
            E.list (\( lon, lat ) -> E.list E.int [ lon, lat ]) Raster.nino34

        _ ->
            E.null


syncJson : Model -> String
syncJson model =
    E.object
        [ ( "markers", E.list markerJson (List.map (beachMarker model) (Model.beaches model) ++ pinMarker model) )
        , ( "points", E.list (waterMarker model >> markerJson) (waterPoints model) )
        , ( "here", E.list markerJson (hereMarker model) )
        , ( "raster", rasterJson model )
        , ( "nino", ninoJson model )
        , ( "trails"
          , E.object
                [ ( "visible", E.bool model.showTrails )
                , ( "selected", E.int (Maybe.withDefault -1 model.trailSelected) )
                ]
          )
        ]
        |> E.encode 0
