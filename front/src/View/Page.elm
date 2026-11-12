module View.Page exposing (view)

{-| The whole page, from the model. The map's `div` stays empty: MapLibre fills it. -}

import Html exposing (Html)
import Layer
import Model exposing (MapState(..), Model)
import Msg exposing (Msg)
import Ui exposing (attr, cls, idAttr)
import View.Bar
import View.Card
import View.Footer
import View.Layers
import View.List
import View.Nav
import View.Sos
import View.Trails
import Words


{-| The map's note when it could not start: the list carries the page.
-}
mapNote : Model -> Html Msg
mapNote model =
    case model.map of
        MapFailed key ->
            Html.p [ idAttr "map-note", cls "map-note", attr "aria-live" "polite" ] [ Html.text (Words.t model key) ]

        _ ->
            Html.p ([ idAttr "map-note", cls "map-note" ] ++ Ui.hidden True) []


{-| The classes the stylesheet reads to dim the dots under the water layer or hide them. They sit
on `main`, not on `#map`: MapLibre owns the map's classes.
-}
mainClass : Model -> String
mainClass model =
    "main"
        ++ (if model.layer == Layer.Water then
                " layer-water"

            else
                ""
           )
        ++ (if model.showBeaches then
                ""

            else
                " no-beaches"
           )


cardSlot : Model -> Html Msg
cardSlot model =
    case View.Trails.picked model of
        Just route ->
            View.Trails.card model route

        Nothing ->
            View.Card.view model


{-| A map that failed to start has no layers to pick.
-}
rail : Model -> List (Html Msg)
rail model =
    case model.map of
        MapFailed _ ->
            []

        _ ->
            [ View.Layers.rail model, View.Layers.key model ]


stage : Model -> Html Msg
stage model =
    Html.main_ [ cls (mainClass model) ]
        (List.concat
            [ [ Html.div [ idAttr "map", attr "role" "application", attr "aria-label" (Words.t model "map.label") ] [] ]
            , rail model
            , View.Sos.view model
            , [ mapNote model, View.List.view model, View.Trails.panel model, cardSlot model ]
            ]
        )


{-| The root keeps the id of the `div` it replaces, which `style.css` reads as `display: contents`.
-}
view : Model -> Html Msg
view model =
    Html.div [ idAttr "app" ]
        (if model.catalogsPending > 0 then
            [ Html.p [ cls "nojs" ] [ Html.text "…" ] ]

         else
            [ View.Nav.view model, View.Bar.header model, View.Bar.hourbar model, stage model, View.Footer.view model ]
        )
