module MapView exposing (beachBounds, drop, syncJson, waveIcon)

{-| What the map shows, as one JSON text for `maplibre_ffi.mjs`: the beach dots, the water-sampling
points, the visitor, the satellite layer and the trail visibility. The map keeps the last text of
each part and redraws only the part that changed.
-}

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
            p.point ++ " (" ++ p.location ++ "): " ++ Water.conditionLabel p.condition model.loc ++ ", " ++ p.sampledOn
    in
    { key = p.point
    , lon = p.lon
    , lat = p.lat
    , label = Just p.point
    , node = Tree.el "div" [ ( "class", "wpoint " ++ Band.cssClass (Water.conditionBand p.condition) ) ] [ drop ]
    , tip = Tree.el "span" [ ( "class", "water" ) ] [ Tree.text text ]
    , tipClass = ""
    , offset = 8
    , click = Nothing
    }


selectedBeach : Model -> Maybe Beach
selectedBeach model =
    model.selected
        |> Maybe.andThen (\name -> Model.beaches model |> List.filter (\b -> b.name == name) |> List.head)


{-| The water layer shows every beach's sampling points; the others only the selected beach's.
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
        [ ( "markers", E.list (beachMarker model >> markerJson) (Model.beaches model) )
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
