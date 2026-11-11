namespace Marola.Client

/// What `maplibre_ffi.mjs` reads as JSON text: the map's configuration and a camera move. They are
/// pure, so a test sees them; the App project only hands the text over.
module MapJson =

    /// What the FFI needs to build the map.
    let mapConfig (lon: float) (lat: float) : string =
        JObj
            [ "lon", JNum lon
              "lat", JNum lat
              "zoom", JNum Config.areaZoom
              "minZoom", JInt Config.areaMinZoom
              "maxZoom", JInt Config.maxZoom
              "style", JStr Config.styleUrl
              "attributions", JArr(Config.attributions |> List.map JStr)
              "module", JStr Config.maplibreModule
              "worker", JStr Config.maplibreWorker ]
        |> Json.render

    let cameraJson (view: Camera) : string =
        match view with
        | Jump(lon, lat, zoom) -> JObj [ "kind", JStr "jump"; "lon", JNum lon; "lat", JNum lat; "zoom", JNum zoom ]
        | Pan(lon, lat) -> JObj [ "kind", JStr "pan"; "lon", JNum lon; "lat", JNum lat ]
        | Fit(west, south, east, north, padding, maxZoom, instant) ->
            JObj
                [ "kind", JStr "fit"
                  "west", JNum west
                  "south", JNum south
                  "east", JNum east
                  "north", JNum north
                  "padding", JInt padding
                  "max_zoom", JInt maxZoom
                  "instant", JBool instant ]
        | Pacific instant -> JObj [ "kind", JStr "pacific"; "instant", JBool instant ]
        | MinZoom zoom -> JObj [ "kind", JStr "minzoom"; "zoom", JInt zoom ]
        |> Json.render
