/// The whole page, from the model. The map itself is not drawn here: its `div` stays empty, and
/// MapLibre fills it.
module Marola.Client.Page

open Marola

/// The map's note when it could not start: the list carries the page.
let private mapNote (model: Model) : Node<Msg> =
    match model.Map with
    | MapFailed key ->
        Vdom.el
            "p"
            [ Vdom.elId "map-note"; Vdom.cls "map-note"; Vdom.attr "aria-live" "polite" ]
            [ Vdom.text (Words.t model key) ]
    | _ -> Vdom.el "p" ([ Vdom.elId "map-note"; Vdom.cls "map-note" ] @ Vdom.hidden true) []

/// The classes the stylesheet reads to dim the dots under the water layer or hide them. They sit on
/// `main`, not on `#map`: MapLibre owns the map's classes.
let private mainClass (model: Model) : string =
    "main"
    + (match model.Layer with
       | Layer.Water -> " layer-water"
       | _ -> "")
    + (if model.ShowBeaches then "" else " no-beaches")

let private cardSlot (model: Model) : Node<Msg> =
    match TrailsView.picked model with
    | Some route -> TrailsView.card model route
    | None -> CardView.view model

/// A map that failed to start has no layers to pick.
let private rail (model: Model) : Node<Msg> list =
    match model.Map with
    | MapFailed _ -> []
    | _ -> [ LayersView.rail model; LayersView.key model ]

let private stage (model: Model) : Node<Msg> =
    Vdom.el
        "main"
        [ Vdom.cls (mainClass model) ]
        (List.concat
            [ [ Vdom.el
                    "div"
                    [ Vdom.elId "map"
                      Vdom.attr "role" "application"
                      Vdom.attr "aria-label" (Words.t model "map.label") ]
                    [] ]
              rail model
              SosView.view model
              [ mapNote model; ListView.view model; TrailsView.panel model; cardSlot model ] ])

let view (model: Model) : Node<Msg> list =
    if model.CatalogsPending > 0 then
        [ Vdom.el "p" [ Vdom.cls "nojs" ] [ Vdom.text "…" ] ]
    else
        NavView.view model
        @ [ BarView.header model
            BarView.hourbar model
            stage model
            FooterView.view model ]
