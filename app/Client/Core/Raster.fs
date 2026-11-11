namespace Marola.Client

open Marola

/// The satellite layers: NASA GIBS raster tiles, keyless and public, fetched only when a visitor
/// picks one. `DaysBack`: VIIRS is complete the next day; MUR SST is published with about a day's lag.
type Raster =
    { Layer: string
      Matrix: string
      Ext: string
      MaxZoom: int
      DaysBack: int
      Opacity: float }

module Raster =

    let private clouds =
        { Layer = "VIIRS_SNPP_CorrectedReflectance_TrueColor"
          Matrix = "GoogleMapsCompatible_Level9"
          Ext = "jpg"
          MaxZoom = 9
          DaysBack = 1
          Opacity = 1.0 }

    let private sst =
        { Layer = "GHRSST_L4_MUR_Sea_Surface_Temperature"
          Matrix = "GoogleMapsCompatible_Level7"
          Ext = "png"
          MaxZoom = 7
          DaysBack = 2
          Opacity = 0.85 }

    let private anomaly =
        { sst with
            Layer = "GHRSST_L4_MUR_Sea_Surface_Temperature_Anomalies" }

    let ofLayer (layer: Layer) : Raster option =
        match layer with
        | Layer.Clouds -> Some clouds
        | Layer.Sst -> Some sst
        | Layer.Anomaly
        | Layer.Elnino -> Some anomaly
        | _ -> None

    /// The imagery day counts back from the day the board was made, not the forecast day: imagery
    /// for a future day does not exist.
    let day (raster: Raster) (today: string) : string = DateFmt.minusDays today raster.DaysBack

    /// `layer/day` names the tiles; the map swaps its source when it changes.
    let id (raster: Raster) (today: string) : string = raster.Layer + "/" + day raster today

    let tilesUrl (raster: Raster) (today: string) : string =
        Config.gibsTiles
        + raster.Layer
        + "/default/"
        + day raster today
        + "/"
        + raster.Matrix
        + "/{z}/{y}/{x}."
        + raster.Ext

    let spec (raster: Raster) (today: string) : Json =
        JObj
            [ "id", JStr(id raster today)
              "tiles", JStr(tilesUrl raster today)
              "maxzoom", JInt raster.MaxZoom
              "opacity", JNum raster.Opacity
              "attribution", JStr Config.gibsAttribution ]

    /// The Nino 3.4 box: 5N to 5S, 170W to 120W, where NOAA measures El Nino.
    let nino34: (int * int) list = [ -170, -5; -120, -5; -120, 5; -170, 5; -170, -5 ]
