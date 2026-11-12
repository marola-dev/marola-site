module View.Layers exposing (key, rail)

{-| The rail of map layers and the key of the one on show. -}

import DateFmt
import Html exposing (Html)
import Html.Keyed
import Layer exposing (Layer)
import Model exposing (Model, Panel(..))
import Msg exposing (Msg(..))
import Raster
import Ui exposing (attr, cls, idAttr)
import Words


iconOf : Layer -> String
iconOf layer =
    case layer of
        Layer.Wind ->
            "wind"

        Layer.Waves ->
            "waves"

        Layer.Water ->
            "droplet"

        Layer.Clouds ->
            "cloud"

        Layer.Sst ->
            "thermometer"

        Layer.Anomaly ->
            "pulse"

        Layer.Elnino ->
            "globe"

        Layer.Off ->
            "list"


{-| A layer that is not built shows as "(soon)" and cannot be pressed.
-}
layerButton : Model -> Layer -> ( String, Html Msg )
layerButton model layer =
    let
        k =
            Layer.key layer

        enabled =
            Layer.enabled layer

        label =
            if enabled then
                Words.t model ("flow." ++ k)

            else
                Words.t model ("flow." ++ k ++ "_soon")

        tail =
            if enabled then
                [ Ui.onClick (LayerPressed layer) ]

            else
                [ cls "soon", Ui.flag "disabled" True ]
    in
    ( k
    , Html.button
        ([ attr "type" "button", attr "data-layer" k, attr "title" label, Words.pressed (model.layer == layer) ] ++ tail)
        [ Words.icon (iconOf layer), Html.span [] [ Html.text label ] ]
    )


toggle : Model -> String -> String -> Bool -> Msg -> ( String, Html Msg )
toggle model k iconName on message =
    ( k
    , Html.button
        [ attr "type" "button", attr "data-toggle" k, attr "title" (Words.t model ("flow." ++ k)), Words.pressed on, Ui.onClick message ]
        [ Words.icon iconName, Html.span [] [ Html.text (Words.t model ("flow." ++ k)) ] ]
    )


{-| Every child has a key so the buttons keep their DOM nodes when the page repaints.
-}
rail : Model -> Html Msg
rail model =
    let
        trailsList =
            ( "trails-list"
            , Html.button
                [ attr "type" "button"
                , attr "aria-controls" "trails-panel"
                , attr "data-panel" "trails"
                , attr "title" (Words.t model "trails.list")
                , Words.expanded (model.panel == TrailList)
                , Ui.onClick TrailPanelToggled
                ]
                [ Words.icon "list", Html.span [] [ Html.text (Words.t model "trails.list") ] ]
            )

        bathymetry =
            ( "bathymetry"
            , Html.button
                [ attr "type" "button", cls "soon", Ui.flag "disabled" True, attr "title" (Words.t model "flow.bathymetry_soon") ]
                [ Words.icon "mountain", Html.span [] [ Html.text (Words.t model "flow.bathymetry_soon") ] ]
            )
    in
    Html.div
        [ idAttr "flow", cls "flow", attr "role" "group", attr "aria-label" (Words.t model "flow.label") ]
        [ Html.Keyed.node "div"
            [ cls "layers" ]
            ([ toggle model "beaches" "pin" model.showBeaches BeachesToggled
             , toggle model "trails" "footprints" model.showTrails TrailsToggled
             , trailsList
             , ( "sep", Html.span [ cls "sep", attr "aria-hidden" "true" ] [] )
             ]
                ++ List.map (layerButton model) Layer.all
                ++ [ bathymetry ]
            )
        ]


ends : String -> String -> Html Msg
ends left right =
    Html.span [ cls "ends" ] [ Html.span [] [ Html.text left ], Html.span [] [ Html.text right ] ]


ramp : String -> Html Msg
ramp kind =
    Html.span [ cls ("ramp " ++ kind), attr "aria-hidden" "true" ] []


{-| The day of the imagery, which is not the day of the board.
-}
whenText : Model -> Layer -> String
whenText model layer =
    case ( Raster.ofLayer layer, model.board ) of
        ( Just r, Just board ) ->
            Raster.day r board.today

        _ ->
            ""


dated : Model -> String -> Layer -> Html Msg
dated model k layer =
    let
        day =
            whenText model layer

        label =
            Words.t model k
    in
    Html.span []
        [ Html.text
            (if day == "" then
                label

             else
                label ++ " " ++ DateFmt.short day model.loc.language
            )
        ]


note : Model -> String -> Html Msg
note model k =
    Html.span [] [ Html.text (Words.t model k) ]


{-| The key under the rail: what the colours mean, for the layer on show.
-}
key : Model -> Html Msg
key model =
    let
        shown =
            case model.layer of
                Layer.Off ->
                    []

                Layer.Wind ->
                    [ ramp "wind", ends "0" "40 km/h", note model "flow.key_wind" ]

                Layer.Waves ->
                    [ ramp "waves", ends "0" "3 m", note model "flow.key_waves" ]

                Layer.Water ->
                    [ note model "flow.key_water" ]

                Layer.Clouds ->
                    [ dated model "flow.key_clouds" Layer.Clouds ]

                Layer.Sst ->
                    [ ramp "sst", ends (Words.t model "flow.cold") (Words.t model "flow.warm"), dated model "flow.key_sst" Layer.Sst ]

                Layer.Anomaly ->
                    [ ramp "anomaly", ends (Words.t model "flow.colder") (Words.t model "flow.warmer"), dated model "flow.key_anomaly" Layer.Anomaly ]

                Layer.Elnino ->
                    [ ramp "anomaly", ends (Words.t model "flow.colder") (Words.t model "flow.warmer"), note model "flow.key_elnino" ]
    in
    Html.div [ idAttr "flowkeys", cls "flowkeys" ]
        (case shown of
            [] ->
                []

            parts ->
                [ Html.p [ cls "flowkey", attr "data-key" (Layer.key model.layer) ] parts ]
        )
