module Raster exposing (Raster, day, id, nino34, ofLayer, spec, tilesUrl)

{-| The satellite layers: NASA GIBS raster tiles, keyless and public, fetched only when a visitor
picks one. `daysBack`: VIIRS is complete the next day; MUR SST comes about a day late.
-}

import Config
import DateFmt
import Json.Encode as E
import Layer exposing (Layer)


type alias Raster =
    { layer : String, matrix : String, ext : String, maxZoom : Int, daysBack : Int, opacity : Float }


clouds : Raster
clouds =
    { layer = "VIIRS_SNPP_CorrectedReflectance_TrueColor", matrix = "GoogleMapsCompatible_Level9", ext = "jpg", maxZoom = 9, daysBack = 1, opacity = 1.0 }


sst : Raster
sst =
    { layer = "GHRSST_L4_MUR_Sea_Surface_Temperature", matrix = "GoogleMapsCompatible_Level7", ext = "png", maxZoom = 7, daysBack = 2, opacity = 0.85 }


anomaly : Raster
anomaly =
    { sst | layer = "GHRSST_L4_MUR_Sea_Surface_Temperature_Anomalies" }


ofLayer : Layer -> Maybe Raster
ofLayer layer =
    case layer of
        Layer.Clouds ->
            Just clouds

        Layer.Sst ->
            Just sst

        Layer.Anomaly ->
            Just anomaly

        Layer.Elnino ->
            Just anomaly

        _ ->
            Nothing


{-| The imagery day counts back from the day the board was made: imagery for a future day does
not exist.
-}
day : Raster -> String -> String
day raster today =
    DateFmt.minusDays today raster.daysBack


id : Raster -> String -> String
id raster today =
    raster.layer ++ "/" ++ day raster today


tilesUrl : Raster -> String -> String
tilesUrl raster today =
    Config.gibsTiles ++ raster.layer ++ "/default/" ++ day raster today ++ "/" ++ raster.matrix ++ "/{z}/{y}/{x}." ++ raster.ext


spec : Raster -> String -> E.Value
spec raster today =
    E.object
        [ ( "id", E.string (id raster today) )
        , ( "tiles", E.string (tilesUrl raster today) )
        , ( "maxzoom", E.int raster.maxZoom )
        , ( "opacity", E.float raster.opacity )
        , ( "attribution", E.string Config.gibsAttribution )
        ]


{-| The Nino 3.4 box: 5N to 5S, 170W to 120W, where NOAA measures El Nino.
-}
nino34 : List ( Int, Int )
nino34 =
    [ ( -170, -5 ), ( -120, -5 ), ( -120, 5 ), ( -170, 5 ), ( -170, -5 ) ]
