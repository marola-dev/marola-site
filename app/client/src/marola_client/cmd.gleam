//// What `update` asks of the world. A value, not an action: the tests read
//// it, and `effects.gleam` is the one place that carries it out.

import marola/language.{type Language}

pub type Camera {
  Jump(lon: Float, lat: Float, zoom: Float)
  Pan(lon: Float, lat: Float)
  /// west, south, east, north; `max_zoom` keeps a lone beach from filling the screen.
  Fit(
    west: Float,
    south: Float,
    east: Float,
    north: Float,
    padding: Int,
    max_zoom: Int,
    instant: Bool,
  )
  /// The Pacific, whose Nino 3.4 box needs a zoom the area's minimum forbids.
  Pacific(instant: Bool)
  MinZoom(Int)
}

pub type Cmd {
  FetchCatalog(Language)
  FetchAreas
  FetchLatest(area: String)
  FetchBoard(area: String, day: String, file: String)
  FetchTrails(area: String)
  ReplaceUrl(path: String, query: String)
  SetDocument(language: String, title: String)
  StoreLanguage(Language)
  InitMap(lon: Float, lat: Float)
  /// The markers, raster and visibility of the map, as one JSON text.
  SyncMap(String)
  /// The GeoJSON of the trail routes.
  SetTrails(String)
  /// The flow layer's field as JSON, or `null` for none.
  SetFlow(String)
  MoveCamera(Camera)
  Locate
  Alert(String)
  Sound(Bool)
  Focus(String)
}
