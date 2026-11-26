module View.Layers exposing (key, player, rail)

{-| The rail of map layers and the key of the one on show.
-}

import Config
import DateFmt
import Html exposing (Html)
import Html.Events
import Html.Keyed
import Icu
import Json.Decode as D
import Layer exposing (Layer)
import Model exposing (Model, Panel(..))
import Msg exposing (Msg(..))
import Raster
import Ui exposing (attr, cls, idAttr)
import Words


{-| The iframe exists only while the player is open, so Spotify is not contacted before a click. Spotify's
compact embed carries its own link to the playlist, so the player is the iframe alone. It sits beside
the layer rail, above the attribution, not inside the rail's scrolling box (which clipped it to a
sliver); the grip at its top edge drags it anywhere over the map: the drag lives in the update (Elm's
own pointer subscriptions); only the moved pixels, which the CSP keeps out of inline styles, go
through a port (ADR 0007).
-}
player : Model -> Html Msg
player model =
    if model.playlistOpen then
        Html.section [ idAttr "player", cls "player", attr "aria-label" (Words.t model "player.label") ]
            [ Html.span
                [ cls "grip"
                , attr "role" "button"
                , attr "tabindex" "0"
                , attr "aria-label" (Words.t model "player.drag")
                , attr "title" (Words.t model "player.drag")
                , Html.Events.preventDefaultOn "mousedown" (D.map2 PlayerDragStarted (D.field "pageX" D.int) (D.field "pageY" D.int) |> D.map (\m -> ( m, True )))
                ]
                []
            , Html.iframe
                [ attr "src" Config.playlistEmbed
                , attr "title" (Words.t model "player.label")
                , attr "allow" "autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture"
                , attr "loading" "lazy"
                ]
                []
            ]

    else
        Html.section ([ idAttr "player", cls "player" ] ++ Ui.hidden True) []


iconOf : Layer -> String
iconOf layer =
    case layer of
        Layer.Wind ->
            "wind"

        Layer.Waves ->
            "waves"

        Layer.Water ->
            "droplet"

        Layer.Scuba ->
            "scuba"

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

        playlist =
            ( "playlist"
            , Html.button
                [ attr "type" "button"
                , attr "data-toggle" "playlist"
                , attr "aria-controls" "player"
                , attr "title" (Words.t model "controls.playlist_title")
                , Words.pressed model.playlistOpen
                , Ui.onClick PlaylistPressed
                ]
                [ Words.icon "music", Html.span [] [ Html.text (Words.t model "controls.playlist") ] ]
            )
    in
    Html.div
        [ idAttr "flow", cls "flow", attr "role" "group", attr "aria-label" (Words.t model "flow.label") ]
        [ Html.Keyed.node "div"
            [ cls "layers" ]
            ([ toggle model "beaches" "pin" model.showBeaches BeachesToggled
             , toggle model "trails" "footprints" model.showTrails TrailsToggled
             , trailsList
             , playlist
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


{-| The area's own file, when it has one: who sampled and when, so a dot never reads as today's.
-}
waterFileKey : Model -> List (Html Msg)
waterFileKey model =
    case model.waterFile of
        Model.WaterFileLoaded file ->
            [ Html.span []
                [ Html.text
                    (Words.ta model
                        "flow.key_water_file"
                        [ ( "source", Icu.Text file.source )
                        , ( "when", Icu.Text (DateFmt.short file.sampledOn model.loc.language) )
                        ]
                    )
                ]
            ]
                ++ (case file.nextBulletin of
                        Just day ->
                            [ Html.span []
                                [ Html.text
                                    (Words.ta model
                                        "flow.key_water_next"
                                        [ ( "when", Icu.Text (DateFmt.short day model.loc.language) ) ]
                                    )
                                ]
                            ]

                        Nothing ->
                            []
                   )

        _ ->
            []


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
                    note model "flow.key_water" :: waterFileKey model

                Layer.Scuba ->
                    [ note model "flow.key_scuba" ]

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
