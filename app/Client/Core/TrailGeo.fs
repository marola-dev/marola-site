namespace Marola.Client

open Marola

/// The trail routes as GeoJSON for the map's line layer. One source, many features: the id of a
/// feature is the position of its route, so a click on the map and a click in the panel name the
/// same route.
module TrailGeo =

    let colour (route: Route) : string =
        Config.bandColour (Difficulty.band route.Difficulty)

    /// The tooltip over a route: its icon, name and length.
    let tip (route: Route) (loc: Locale) : Node<unit> =
        Vdom.el
            "span"
            []
            [ Icons.icon "footprints"
              Vdom.text (" " + route.Name + " · " + Fmt.value loc (Some route.LengthKm) " km" 1) ]

    let private coordinates (line: Point list) : Json =
        JArr(line |> List.map (fun p -> JArr [ JNum p.Lon; JNum p.Lat ]))

    let private feature (id: int) (route: Route) (loc: Locale) : Json option =
        match Trails.drawableLines route with
        | [] -> None
        | lines ->
            Some(
                JObj
                    [ "type", JStr "Feature"
                      "properties",
                      JObj
                          [ "id", JInt id
                            "color", JStr(colour route)
                            // MapLibre keeps a property that is not a number or text as text anyway;
                            // the map parses this one back into DOM nodes.
                            "tip", JStr(Json.render (Vdom.toJson (tip route loc))) ]
                      "geometry",
                      JObj
                          [ "type", JStr "MultiLineString"
                            "coordinates", JArr(List.map coordinates lines) ] ]
            )

    /// A route with no drawable line is left out, but keeps its id.
    let collection (trails: Trails option) (loc: Locale) : string =
        let features =
            match trails with
            | None -> []
            | Some found ->
                Trails.routes found
                |> List.mapi (fun id route -> feature id route loc)
                |> List.choose Operators.id

        JObj [ "type", JStr "FeatureCollection"; "features", JArr features ]
        |> Json.render
