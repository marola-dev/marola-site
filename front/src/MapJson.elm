module MapJson exposing (cameraJson, mapConfig)

{-| What `maplibre_ffi.mjs` reads as JSON text: the map's configuration and a camera move. -}

import Config
import Effect exposing (Camera(..))
import Json.Encode as E


mapConfig : Float -> Float -> String
mapConfig lon lat =
    E.object
        [ ( "lon", E.float lon )
        , ( "lat", E.float lat )
        , ( "zoom", E.float Config.areaZoom )
        , ( "minZoom", E.int Config.areaMinZoom )
        , ( "maxZoom", E.int Config.maxZoom )
        , ( "style", E.string Config.styleUrl )
        , ( "attributions", E.list E.string Config.attributions )
        , ( "module", E.string Config.maplibreModule )
        , ( "worker", E.string Config.maplibreWorker )
        ]
        |> E.encode 0


cameraJson : Camera -> String
cameraJson view =
    (case view of
        Jump lon lat zoom ->
            [ ( "kind", E.string "jump" ), ( "lon", E.float lon ), ( "lat", E.float lat ), ( "zoom", E.float zoom ) ]

        Pan lon lat ->
            [ ( "kind", E.string "pan" ), ( "lon", E.float lon ), ( "lat", E.float lat ) ]

        Fit west south east north padding maxZoom instant ->
            [ ( "kind", E.string "fit" )
            , ( "west", E.float west )
            , ( "south", E.float south )
            , ( "east", E.float east )
            , ( "north", E.float north )
            , ( "padding", E.int padding )
            , ( "max_zoom", E.int maxZoom )
            , ( "instant", E.bool instant )
            ]

        Pacific instant ->
            [ ( "kind", E.string "pacific" ), ( "instant", E.bool instant ) ]

        MinZoom zoom ->
            [ ( "kind", E.string "minzoom" ), ( "zoom", E.int zoom ) ]
    )
        |> E.object
        |> E.encode 0
