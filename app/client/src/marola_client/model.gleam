//// Everything the page knows. The view reads it, `update` changes it, and
//// nothing else does.

import gleam/list
import gleam/option.{type Option, None, Some}
import marola/area.{type Area}
import marola/beach.{type Selection, BestHour}
import marola/board.{type Board}
import marola/geo.{type Point}
import marola/i18n.{type Locale}
import marola/trails.{type Trails}
import marola_client/config
import marola_client/latest.{type Day}
import marola_client/params.{type Query}

/// The map layer on show. `Off` is none; the others are the buttons of the rail.
pub type Layer {
  Off
  Wind
  Waves
  Water
  Clouds
  Sst
  Anomaly
  Elnino
}

pub const layers = [Wind, Waves, Water, Clouds, Sst, Anomaly, Elnino]

pub fn layer_key(layer: Layer) -> String {
  case layer {
    Off -> "off"
    Wind -> "wind"
    Waves -> "waves"
    Water -> "water"
    Clouds -> "clouds"
    Sst -> "sst"
    Anomaly -> "anomaly"
    Elnino -> "elnino"
  }
}

pub fn layer_of_key(key: String) -> Result(Layer, Nil) {
  list.find(layers, fn(layer) { layer_key(layer) == key })
}

/// A layer whose button works; the rest show as "em breve".
pub fn layer_enabled(layer: Layer) -> Bool {
  list.contains(config.enabled_layers, layer_key(layer))
}

/// What the map is doing. A failed map keeps the page usable through the list.
pub type MapState {
  MapNone
  MapLoading
  MapReady
  MapFailed(note_key: String)
}

/// The footer's line while the page loads or when it could not.
pub type Status {
  Loading(name: String)
  Failed(error: String, missing: Bool)
  NoAreas
  /// A board whose schema this page does not read.
  TooNew(schema: Int)
  Idle
}

pub type TrailsFile {
  TrailsPending
  TrailsLoaded(Trails)
  /// No file for the area: the board's own trails stand in.
  TrailsMissing
}

/// The one panel that may fill the map's left edge.
pub type Panel {
  Closed
  BeachList
  TrailList
}

pub type Model {
  Model(
    loc: Locale,
    catalogs_pending: Int,
    path: String,
    query: Query,
    areas: List(Area),
    area: Option(Area),
    days: List(Day),
    day: Option(String),
    board: Option(Board),
    hours: List(String),
    selection: Selection,
    selected: Option(String),
    here: Option(Point),
    layer: Layer,
    show_beaches: Bool,
    show_trails: Bool,
    panel: Panel,
    trail_selected: Option(Int),
    trails_file: TrailsFile,
    lore_open: Bool,
    blurb_open: Bool,
    sos_open: Bool,
    sound_on: Bool,
    map: MapState,
    status: Status,
    zoomed_out: Bool,
    fitted: Bool,
    reduced_motion: Bool,
  )
}

/// The trails to draw: the area's file, else the board's own.
pub fn trails(model: Model) -> Option(Trails) {
  case model.trails_file, model.area, model.board {
    TrailsLoaded(found), _, _ -> Some(found)
    TrailsMissing, Some(area), Some(board) ->
      Some(trails.from_board(area.id, board.trails))
    _, _, _ -> None
  }
}

pub fn initial(
  loc: Locale,
  path: String,
  query: Query,
  reduced_motion: Bool,
) -> Model {
  Model(
    loc:,
    catalogs_pending: 2,
    path:,
    query:,
    areas: [],
    area: None,
    days: [],
    day: None,
    board: None,
    hours: [],
    selection: BestHour,
    selected: None,
    here: None,
    layer: Off,
    show_beaches: True,
    show_trails: True,
    panel: Closed,
    trail_selected: None,
    trails_file: TrailsPending,
    lore_open: False,
    blurb_open: False,
    sos_open: False,
    sound_on: False,
    map: MapNone,
    status: Idle,
    zoomed_out: False,
    fitted: False,
    reduced_motion:,
  )
}
