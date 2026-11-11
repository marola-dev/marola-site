//// The satellite layers: NASA GIBS raster tiles, keyless and public, fetched
//// only when a visitor picks one.

import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import marola/datefmt
import marola_client/config
import marola_client/model.{type Layer} as mdl

/// `days_back`: VIIRS is complete the next day; MUR SST is published with
/// about a day's lag.
pub type Raster {
  Raster(
    layer: String,
    matrix: String,
    ext: String,
    maxzoom: Int,
    days_back: Int,
    opacity: Float,
  )
}

const clouds =
  Raster(
    "VIIRS_SNPP_CorrectedReflectance_TrueColor",
    "GoogleMapsCompatible_Level9",
    "jpg",
    9,
    1,
    1.0,
  )

const sst =
  Raster(
    "GHRSST_L4_MUR_Sea_Surface_Temperature",
    "GoogleMapsCompatible_Level7",
    "png",
    7,
    2,
    0.85,
  )

const anomaly =
  Raster(
    "GHRSST_L4_MUR_Sea_Surface_Temperature_Anomalies",
    "GoogleMapsCompatible_Level7",
    "png",
    7,
    2,
    0.85,
  )

pub fn of_layer(layer: Layer) -> Option(Raster) {
  case layer {
    mdl.Clouds -> Some(clouds)
    mdl.Sst -> Some(sst)
    mdl.Anomaly | mdl.Elnino -> Some(anomaly)
    _ -> None
  }
}

/// The imagery day counts back from the day the board was made, not the
/// forecast day: imagery for a future day does not exist.
pub fn day(raster: Raster, today: String) -> String {
  datefmt.minus_days(today, raster.days_back)
}

/// `layer/day` names the tiles; the map swaps its source when it changes.
pub fn id(raster: Raster, today: String) -> String {
  raster.layer <> "/" <> day(raster, today)
}

pub fn tiles_url(raster: Raster, today: String) -> String {
  config.gibs_tiles
  <> raster.layer
  <> "/default/"
  <> day(raster, today)
  <> "/"
  <> raster.matrix
  <> "/{z}/{y}/{x}."
  <> raster.ext
}

pub fn spec(raster: Raster, today: String) -> Json {
  json.object([
    #("id", json.string(id(raster, today))),
    #("tiles", json.string(tiles_url(raster, today))),
    #("maxzoom", json.int(raster.maxzoom)),
    #("opacity", json.float(raster.opacity)),
    #("attribution", json.string(config.gibs_attribution)),
  ])
}

/// The Nino 3.4 box: 5N to 5S, 170W to 120W, where NOAA measures El Nino.
pub fn nino34() -> List(#(Int, Int)) {
  [#(-170, -5), #(-120, -5), #(-120, 5), #(-170, 5), #(-170, -5)]
}
