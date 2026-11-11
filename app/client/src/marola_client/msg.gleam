//// What can happen on the page.

import gleam/dict.{type Dict}
import marola/area.{type Area}
import marola/geo.{type Point}
import marola/language.{type Language}
import marola/trails.{type Trails}
import marola_client/boards.{type Loaded}
import marola_client/latest.{type Day}
import marola_client/model.{type Layer}
import rsvp

pub type Fold {
  LoreFold
  BlurbFold
}

pub type Msg {
  // Data arrived, or did not.
  CatalogLoaded(Language, Result(Dict(String, String), rsvp.Error))
  AreasLoaded(Result(List(Area), rsvp.Error))
  LatestLoaded(area: String, result: Result(List(Day), rsvp.Error))
  BoardLoaded(
    area: String,
    day: String,
    file: String,
    result: Result(Loaded, rsvp.Error),
  )
  TrailsFileLoaded(area: String, result: Result(Trails, rsvp.Error))
  // The visitor.
  AreaPicked(String)
  DayPicked(String)
  /// The slider's position: -1 is each beach at its own best hour.
  HourMoved(Int)
  /// `pan` is true from the list and false from the map, where it is already in view.
  BeachPicked(name: String, pan: Bool)
  CardClosed
  LayerPressed(Layer)
  BeachesToggled
  TrailsToggled
  ListToggled
  TrailPanelToggled
  /// `fit` is true from the panel, which names a route the map may not show.
  TrailChosen(id: Int, fit: Bool)
  NearPressed
  Located(Result(Point, String))
  FoldToggled(Fold)
  SosToggled
  SosClosed
  LanguagePicked(Language)
  SoundPressed
  SoundFailed
  /// An event of the map, named by `maplibre_ffi.mjs`: `ready`, `error`,
  /// `click`, `beach` and `trail`; `arg` is the beach name or the route id.
  MapEvent(kind: String, arg: String)
}
