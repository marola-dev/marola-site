/// The rail of map layers and the key of the one on show.
module Marola.Client.LayersView

open Marola

let private iconOf (layer: Layer) : string =
    match layer with
    | Layer.Wind -> "wind"
    | Layer.Waves -> "waves"
    | Layer.Water -> "droplet"
    | Layer.Clouds -> "cloud"
    | Layer.Sst -> "thermometer"
    | Layer.Anomaly -> "pulse"
    | Layer.Elnino -> "globe"
    | Layer.Off -> "list"

/// A layer that is not built shows as "(soon)" and cannot be pressed.
let private layerButton (model: Model) (layer: Layer) : Node<Msg> =
    let key = Layer.key layer
    let enabled = Layer.enabled layer

    let label =
        if enabled then
            Words.t model ("flow." + key)
        else
            Words.t model ("flow." + key + "_soon")

    let tail =
        if enabled then
            [ Vdom.onClick (LayerPressed layer) ]
        else
            [ Vdom.cls "soon"; Flag("disabled", true) ]

    Vdom.keyed
        key
        (Vdom.el
            "button"
            ([ Vdom.attr "type" "button"
               Vdom.attr "data-layer" key
               Vdom.attr "title" label
               Words.pressed (model.Layer = layer) ]
             @ tail)
            [ Words.icon (iconOf layer); Vdom.el "span" [] [ Vdom.text label ] ])

let private toggle (model: Model) (key: string) (iconName: string) (on: bool) (message: Msg) : Node<Msg> =
    Vdom.keyed
        key
        (Vdom.el
            "button"
            [ Vdom.attr "type" "button"
              Vdom.attr "data-toggle" key
              Vdom.attr "title" (Words.t model ("flow." + key))
              Words.pressed on
              Vdom.onClick message ]
            [ Words.icon iconName
              Vdom.el "span" [] [ Vdom.text (Words.t model ("flow." + key)) ] ])

let rail (model: Model) : Node<Msg> =
    // Every child has a key so the buttons keep their DOM nodes when the page repaints.
    let trailsList =
        Vdom.keyed
            "trails-list"
            (Vdom.el
                "button"
                [ Vdom.attr "type" "button"
                  Vdom.attr "aria-controls" "trails-panel"
                  Vdom.attr "data-panel" "trails"
                  Vdom.attr "title" (Words.t model "trails.list")
                  Words.expanded (model.Panel = Panel.TrailList)
                  Vdom.onClick TrailPanelToggled ]
                [ Words.icon "list"
                  Vdom.el "span" [] [ Vdom.text (Words.t model "trails.list") ] ])

    let bathymetry =
        Vdom.keyed
            "bathymetry"
            (Vdom.el
                "button"
                [ Vdom.attr "type" "button"
                  Vdom.cls "soon"
                  Flag("disabled", true)
                  Vdom.attr "title" (Words.t model "flow.bathymetry_soon") ]
                [ Words.icon "mountain"
                  Vdom.el "span" [] [ Vdom.text (Words.t model "flow.bathymetry_soon") ] ])

    Vdom.el
        "div"
        [ Vdom.elId "flow"
          Vdom.cls "flow"
          Vdom.attr "role" "group"
          Vdom.attr "aria-label" (Words.t model "flow.label") ]
        [ Vdom.el
              "div"
              [ Vdom.cls "layers" ]
              ([ toggle model "beaches" "pin" model.ShowBeaches BeachesToggled
                 toggle model "trails" "footprints" model.ShowTrails TrailsToggled
                 trailsList
                 Vdom.keyed "sep" (Vdom.el "span" [ Vdom.cls "sep"; Vdom.attr "aria-hidden" "true" ] []) ]
               @ (Layer.all |> List.map (layerButton model))
               @ [ bathymetry ]) ]

let private ends (left: string) (right: string) : Node<Msg> =
    Vdom.el "span" [ Vdom.cls "ends" ] [ Vdom.el "span" [] [ Vdom.text left ]; Vdom.el "span" [] [ Vdom.text right ] ]

let private ramp (kind: string) : Node<Msg> =
    Vdom.el "span" [ Vdom.cls ("ramp " + kind); Vdom.attr "aria-hidden" "true" ] []

/// The day of the imagery, which is not the day of the board.
let private whenText (model: Model) (layer: Layer) : string =
    match Raster.ofLayer layer, model.Board with
    | Some r, Some board -> Raster.day r board.Today
    | _ -> ""

let private dated (model: Model) (key: string) (layer: Layer) : Node<Msg> =
    let day = whenText model layer
    let label = Words.t model key

    Vdom.el
        "span"
        []
        [ Vdom.text (
              if day = "" then
                  label
              else
                  label + " " + DateFmt.short day model.Loc.Language
          ) ]

let private note (model: Model) (key: string) : Node<Msg> =
    Vdom.el "span" [] [ Vdom.text (Words.t model key) ]

/// The key under the rail: what the colours mean, for the layer on show.
let key (model: Model) : Node<Msg> =
    let shown =
        match model.Layer with
        | Layer.Off -> []
        | Layer.Wind -> [ ramp "wind"; ends "0" "40 km/h"; note model "flow.key_wind" ]
        | Layer.Waves -> [ ramp "waves"; ends "0" "3 m"; note model "flow.key_waves" ]
        | Layer.Water -> [ note model "flow.key_water" ]
        | Layer.Clouds -> [ dated model "flow.key_clouds" Layer.Clouds ]
        | Layer.Sst ->
            [ ramp "sst"
              ends (Words.t model "flow.cold") (Words.t model "flow.warm")
              dated model "flow.key_sst" Layer.Sst ]
        | Layer.Anomaly ->
            [ ramp "anomaly"
              ends (Words.t model "flow.colder") (Words.t model "flow.warmer")
              dated model "flow.key_anomaly" Layer.Anomaly ]
        | Layer.Elnino ->
            [ ramp "anomaly"
              ends (Words.t model "flow.colder") (Words.t model "flow.warmer")
              note model "flow.key_elnino" ]

    Vdom.el
        "div"
        [ Vdom.elId "flowkeys"; Vdom.cls "flowkeys" ]
        (match shown with
         | [] -> []
         | parts -> [ Vdom.el "p" [ Vdom.cls "flowkey"; Vdom.attr "data-key" (Layer.key model.Layer) ] parts ])
