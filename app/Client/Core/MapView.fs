namespace Marola.Client

open Marola

/// What the map shows, as one JSON text for `maplibre_ffi.mjs`: the beach dots, the water-sampling
/// points, the visitor, the satellite layer and the trail visibility. The map keeps the last text
/// of each part and redraws only the part that changed.
module MapView =

    /// The west, south, east and north edges of the beaches, or none.
    let beachBounds (board: Board) : (float * float * float * float) option =
        match board.Beaches with
        | [] -> None
        | first :: rest ->
            rest
            |> List.fold
                (fun (w, s, e, n) (b: Beach) -> min w b.Lon, min s b.Lat, max e b.Lon, max n b.Lat)
                (first.Lon, first.Lat, first.Lon, first.Lat)
            |> Some

    type private Marker =
        { Key: string
          Lon: float
          Lat: float
          Label: string option
          Node: Node<unit>
          Tip: Node<unit>
          TipClass: string
          Offset: int
          Click: string option }

    let private markerJson (m: Marker) : Json =
        JObj
            [ "key", JStr m.Key
              "lon", JNum m.Lon
              "lat", JNum m.Lat
              "label", Json.nullable JStr m.Label
              "node", Vdom.toJson m.Node
              "tip", Vdom.toJson m.Tip
              "tip_class", JStr m.TipClass
              "offset", JInt m.Offset
              "click", Json.nullable JStr m.Click ]

    let private num (n: float) : string = Parse.shortest n

    /// A beach is a dot in its score colour: a white ring keeps neighbours apart where beaches
    /// crowd, and the picked one grows into a badge with its number. The colour is a class, never
    /// an inline style: the CSP blocks `style=`.
    let waveIcon (bandClass: string) (selected: bool) (score: int option) : Node<unit> =
        let size = if selected then 32.0 else 16.0
        let r = size / 2.0

        let label =
            match selected, score with
            | true, Some s ->
                [ Vdom.svg
                      "text"
                      [ Vdom.attr "x" "16"
                        Vdom.attr "y" "20.5"
                        Vdom.attr "text-anchor" "middle"
                        Vdom.attr "font-size" "13"
                        Vdom.attr "font-weight" "600"
                        Vdom.cls (if bandClass = "c40" then "num dark" else "num") ]
                      [ Vdom.text (string s) ] ]
            | _ -> []

        Vdom.svg
            "svg"
            [ Vdom.attr "viewBox" ("0 0 " + num size + " " + num size)
              Vdom.attr "width" (num size)
              Vdom.attr "height" (num size)
              Vdom.attr "aria-hidden" "true" ]
            ([ Vdom.svg
                   "circle"
                   [ Vdom.attr "cx" (num r)
                     Vdom.attr "cy" (num r)
                     Vdom.attr "r" (num (r - 0.5))
                     Vdom.attr "fill" "#1d2733" ]
                   []
               Vdom.svg
                   "circle"
                   [ Vdom.attr "cx" (num r)
                     Vdom.attr "cy" (num r)
                     Vdom.attr "r" (num (r - 2.0))
                     Vdom.cls ("dot f-" + bandClass)
                     Vdom.attr "stroke" "#fff"
                     Vdom.attr "stroke-width" "2" ]
                   [] ]
             @ label)

    let private beachMarker (model: Model) (b: Beach) : Marker =
        let shown = Beach.shown b model.Selection
        let score = shown |> Option.map (fun s -> s.Score)
        let selected = model.Selected = Some b.Name

        let past =
            match shown, model.Board with
            | Some s, Some board -> Board.isPast board s.H
            | _ -> false

        let cls =
            "wave" + (if selected then " selected" else "") + (if past then " past" else "")

        let bandClass = Band.cssClass (Band.ofScore score b.Water.Unfit)
        let tip = Aspects.ofBeach b shown model.Loc

        { Key = b.Name
          Lon = b.Lon
          Lat = b.Lat
          Label = Some b.Name
          Node = Vdom.el "div" [ Vdom.cls cls ] [ waveIcon bandClass selected score ]
          Tip = Vdom.el "div" [] (AspectsView.children tip)
          TipClass = "aspects"
          Offset = (if selected then 18 else 10)
          Click = Some "beach" }

    /// Lucide's droplet, so a sampling point never reads as a beach dot; `style.css` fills it by band.
    let drop () : Node<unit> =
        let d =
            "M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z"

        Vdom.svg
            "svg"
            [ Vdom.attr "viewBox" "0 0 24 24"
              Vdom.attr "aria-hidden" "true"
              Vdom.attr "focusable" "false" ]
            [ Vdom.svg "path" [ Vdom.cls "rim"; Vdom.attr "d" d ] []
              Vdom.svg "path" [ Vdom.cls "fill"; Vdom.attr "d" d ] [] ]

    let private waterMarker (model: Model) (p: WaterPoint) : Marker =
        let bandClass = Band.cssClass (Condition.band p.Condition)

        let text =
            p.Point
            + " ("
            + p.Location
            + "): "
            + Condition.label p.Condition model.Loc
            + ", "
            + p.SampledOn

        { Key = p.Point
          Lon = p.Lon
          Lat = p.Lat
          Label = Some p.Point
          Node = Vdom.el "div" [ Vdom.cls ("wpoint " + bandClass) ] [ drop () ]
          Tip = Vdom.el "span" [ Vdom.cls "water" ] [ Vdom.text text ]
          TipClass = ""
          Offset = 8
          Click = None }

    let private selectedBeach (model: Model) : Beach option =
        model.Selected
        |> Option.bind (fun name -> Model.beaches model |> List.tryFind (fun b -> b.Name = name))

    /// The water layer shows every beach's sampling points; the others only the selected beach's.
    let private waterPoints (model: Model) : WaterPoint list =
        let shown =
            match model.Layer, selectedBeach model with
            | Layer.Water, _ -> Model.beaches model
            | _, Some b -> [ b ]
            | _, None -> []

        shown |> List.collect (fun b -> b.Water.Points)

    let private hereMarker (model: Model) : Marker list =
        match model.Here with
        | None -> []
        | Some p ->
            [ { Key = "here"
                Lon = p.Lon
                Lat = p.Lat
                Label = None
                Node = Vdom.el "div" [ Vdom.cls "here" ] []
                Tip = Vdom.el "span" [] [ Vdom.text (I18n.t model.Loc "near.you" []) ]
                TipClass = ""
                Offset = 8
                Click = None } ]

    let private rasterJson (model: Model) : Json =
        match Raster.ofLayer model.Layer, model.Board with
        | Some r, Some board -> Raster.spec r board.Today
        | _ -> JNull

    let private ninoJson (model: Model) : Json =
        match model.Layer with
        | Layer.Elnino -> JArr(Raster.nino34 |> List.map (fun (lon, lat) -> JArr [ JInt lon; JInt lat ]))
        | _ -> JNull

    let syncJson (model: Model) : string =
        JObj
            [ "markers", JArr(Model.beaches model |> List.map (beachMarker model >> markerJson))
              "points", JArr(waterPoints model |> List.map (waterMarker model >> markerJson))
              "here", JArr(hereMarker model |> List.map markerJson)
              "raster", rasterJson model
              "nino", ninoJson model
              "trails",
              JObj
                  [ "visible", JBool model.ShowTrails
                    "selected", JInt(Option.defaultValue -1 model.TrailSelected) ] ]
        |> Json.render
