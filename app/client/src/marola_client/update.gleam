//// The page's one state machine: a message and a model in, a model and a list
//// of commands out. Nothing here touches the browser, so every path is a test.
//// The work sits in `update/load` (data arriving) and `update/visit` (the
//// visitor); this module starts the page and sends each message to its part.

import gleam/dict
import gleam/list
import gleam/option.{type Option, Some}
import marola/i18n.{Locale}
import marola/language
import marola_client/cmd.{type Cmd}
import marola_client/model.{type Model, Model} as mdl
import marola_client/msg.{type Msg}
import marola_client/params.{type Query}
import marola_client/update/load
import marola_client/update/support.{fail, guard_area, guard_day, sync}
import marola_client/update/visit

/// What the page reads from the browser before it starts.
pub type Env {
  Env(
    path: String,
    query: Query,
    languages: List(String),
    stored_language: Option(String),
    reduced_motion: Bool,
  )
}

pub fn init(env: Env) -> #(Model, List(Cmd)) {
  let language =
    language.resolve(
      param: params.get(env.query, "lang"),
      stored: env.stored_language,
      languages: env.languages,
      supported: language.all,
    )
  let loc = Locale(catalog: dict.new(), language: language)
  let base = mdl.initial(loc, env.path, env.query, env.reduced_motion)
  let layer =
    params.get(env.query, "layer")
    |> option.map(mdl.layer_of_key)
    |> option.map(fn(found) {
      case found {
        Ok(layer) ->
          case mdl.layer_enabled(layer) {
            True -> layer
            False -> mdl.Off
          }
        Error(Nil) -> mdl.Off
      }
    })
    |> option.unwrap(mdl.Off)
  let start =
    Model(
      ..base,
      layer:,
      show_beaches: params.get(env.query, "beaches") != Some("0"),
      show_trails: params.get(env.query, "trails") != Some("0"),
      zoomed_out: layer == mdl.Elnino,
    )
  #(start, list.map(language.all, cmd.FetchCatalog))
}

pub fn update(model: Model, message: Msg) -> #(Model, List(Cmd)) {
  case message {
    msg.CatalogLoaded(language, result) ->
      load.catalog_loaded(model, language, result)
    msg.AreasLoaded(Ok(areas)) -> load.areas_loaded(model, areas)
    msg.AreasLoaded(Error(e)) -> fail(model, e, "data/areas.json")
    msg.LatestLoaded(area, Ok(days)) -> load.latest_loaded(model, area, days)
    msg.LatestLoaded(area, Error(e)) ->
      guard_area(model, area, fn() {
        fail(model, e, "data/" <> area <> "/latest.json")
      })
    msg.BoardLoaded(area, day, file, result) ->
      guard_day(model, area, day, fn() {
        load.board_loaded(model, area, file, result)
      })
    msg.TrailsFileLoaded(area, result) ->
      guard_area(model, area, fn() { load.trails_loaded(model, result) })
    msg.AreaPicked(id) -> load.area_picked(model, id)
    msg.DayPicked(day) -> load.day_picked(model, day)
    msg.HourMoved(index) -> visit.hour_moved(model, index)
    msg.BeachPicked(name, pan) -> visit.beach_picked(model, name, pan)
    msg.CardClosed -> visit.close_cards(model)
    msg.LayerPressed(layer) -> visit.layer_pressed(model, layer)
    msg.BeachesToggled -> visit.toggled(model, "beaches", !model.show_beaches)
    msg.TrailsToggled -> visit.toggled(model, "trails", !model.show_trails)
    msg.ListToggled -> visit.panel_toggled(model, mdl.BeachList)
    msg.TrailPanelToggled -> visit.panel_toggled(model, mdl.TrailList)
    msg.TrailChosen(id, fit) -> visit.trail_chosen(model, id, fit)
    msg.NearPressed -> visit.near_pressed(model)
    msg.Located(Ok(point)) ->
      sync(Model(..model, here: Some(point), panel: mdl.BeachList), [])
    msg.Located(Error(_)) -> #(model, [
      cmd.Alert(i18n.t(model.loc, "near.denied", [])),
    ])
    msg.FoldToggled(fold) -> #(visit.fold_toggled(model, fold), [])
    msg.SosToggled -> #(Model(..model, sos_open: !model.sos_open), [])
    msg.SosClosed -> visit.sos_closed(model)
    msg.LanguagePicked(language) -> visit.language_picked(model, language)
    msg.SoundPressed -> #(Model(..model, sound_on: !model.sound_on), [
      cmd.Sound(!model.sound_on),
    ])
    msg.SoundFailed -> #(Model(..model, sound_on: False), [])
    msg.MapEvent(kind, arg) -> visit.map_event(model, kind, arg)
  }
}
