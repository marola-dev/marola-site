//// The part of `update` that answers data arriving: catalogs, areas, days,
//// boards and trails, and the choice of an area or a day that starts a load.

import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import marola/area.{type Area}
import marola/beach.{BestHour}
import marola/board.{type Board}
import marola/i18n.{Locale}
import marola/language.{type Language}
import marola/trails
import marola_client/boards
import marola_client/cmd.{type Cmd}
import marola_client/config
import marola_client/latest.{type Day}
import marola_client/map_view
import marola_client/model.{type Model, Model} as mdl
import marola_client/params
import marola_client/update/support.{
  active, delete_param, describe, fail, flow_cmds, guard_area, set_param, sync,
  trail_cmds, url,
}
import rsvp

pub fn catalog_loaded(
  model: Model,
  language: Language,
  result: Result(dict.Dict(String, String), rsvp.Error),
) -> #(Model, List(Cmd)) {
  let catalog = case result {
    Ok(messages) -> dict.insert(model.loc.catalog, language, messages)
    Error(_) -> model.loc.catalog
  }
  let pending = model.catalogs_pending - 1
  let next =
    Model(
      ..model,
      loc: Locale(..model.loc, catalog:),
      catalogs_pending: pending,
    )
  let next = case result {
    Error(e) ->
      Model(
        ..next,
        status: mdl.Failed(
          describe(e, "i18n/" <> language.tag(language) <> ".json").0,
          False,
        ),
      )
    Ok(_) -> next
  }
  case pending {
    0 -> #(next, [
      cmd.SetDocument(
        language.tag(model.loc.language),
        i18n.t(next.loc, "title.map", []),
      ),
      cmd.FetchAreas,
    ])
    _ -> #(next, [])
  }
}

pub fn areas_loaded(model: Model, areas: List(Area)) -> #(Model, List(Cmd)) {
  let wanted = params.get(model.query, "area")
  let chosen =
    list.find(areas, fn(a) { Some(a.id) == wanted })
    |> option.from_result
    |> option.or(list.first(areas) |> option.from_result)
  case chosen {
    None -> #(Model(..model, areas:, status: mdl.NoAreas), [])
    Some(area) -> select_area(Model(..model, areas:), area)
  }
}

fn select_area(model: Model, area: Area) -> #(Model, List(Cmd)) {
  let first_map = model.map == mdl.MapNone
  let next =
    Model(
      ..model,
      area: Some(area),
      status: mdl.Loading(area.name),
      trails_file: mdl.TrailsPending,
      trail_selected: None,
      map: case first_map {
        True -> mdl.MapLoading
        False -> model.map
      },
    )
    |> set_param("area", area.id)
  let map_cmd = case first_map {
    True -> cmd.InitMap(area.lon, area.lat)
    False -> cmd.MoveCamera(cmd.Jump(area.lon, area.lat, config.area_zoom))
  }
  #(next, [
    url(next),
    map_cmd,
    cmd.FetchLatest(area.id),
    cmd.FetchTrails(area.id),
  ])
}

pub fn area_picked(model: Model, id: String) -> #(Model, List(Cmd)) {
  case list.find(model.areas, fn(a) { a.id == id }) {
    Error(Nil) -> #(model, [])
    Ok(area) -> {
      // A new area starts afresh: no beach picked, the map fits its beaches.
      let reset =
        Model(..model, fitted: False, selected: None, board: None, day: None)
        |> delete_param("beach")
        |> delete_param("day")
      let #(next, cmds) = select_area(reset, area)
      #(next, list.append(cmds, sync(next, []).1))
    }
  }
}

pub fn latest_loaded(
  model: Model,
  area: String,
  days: List(Day),
) -> #(Model, List(Cmd)) {
  use <- guard_area(model, area)
  let wanted = params.get(model.query, "day")
  let by_param =
    list.find(days, fn(d) { Some(d.day) == wanted }) |> option.from_result
  case option.or(by_param, list.last(days) |> option.from_result) {
    None -> #(
      Model(..model, days:, status: mdl.Failed("no days " <> area, False)),
      [],
    )
    Some(day) -> select_day(Model(..model, days:), day)
  }
}

fn select_day(model: Model, day: Day) -> #(Model, List(Cmd)) {
  let next =
    Model(..model, day: Some(day.day), status: mdl.Loading(day.day))
    |> set_param("day", day.day)
  let area = option.map(model.area, fn(a) { a.id }) |> option.unwrap("")
  #(next, [url(next), cmd.FetchBoard(area, day.day, day.file)])
}

pub fn day_picked(model: Model, day: String) -> #(Model, List(Cmd)) {
  case list.find(model.days, fn(d) { d.day == day }) {
    Ok(found) -> select_day(model, found)
    Error(Nil) -> #(model, [])
  }
}

pub fn board_loaded(
  model: Model,
  area: String,
  file: String,
  result: Result(boards.Loaded, rsvp.Error),
) -> #(Model, List(Cmd)) {
  case result {
    Error(e) -> fail(model, e, "data/" <> area <> "/" <> file)
    Ok(boards.Newer(schema)) -> #(
      Model(..model, status: mdl.TooNew(schema)),
      [],
    )
    Ok(boards.Read(board)) -> show_board(model, board)
  }
}

fn show_board(model: Model, board: Board) -> #(Model, List(Cmd)) {
  let hours = board.hours(board)
  let from_url = case params.get(model.query, "beach"), model.selected {
    Some(name), None ->
      case list.find(board.beaches, fn(b) { b.name == name }) {
        Ok(_) -> Some(name)
        Error(Nil) -> None
      }
    _, selected -> selected
  }
  let next =
    Model(
      ..model,
      board: Some(board),
      hours:,
      selection: BestHour,
      selected: from_url,
      status: mdl.Idle,
    )
  let #(fitted, fit) = fit(next)
  let next = Model(..next, fitted:)
  sync(next, list.flatten([fit, trail_cmds(next), flow_cmds(next)]))
}

/// The first board of an area fits the map to its beaches; a picked layer
/// that zoomed the map out keeps its view.
fn fit(model: Model) -> #(Bool, List(Cmd)) {
  case model.board, model.fitted || model.zoomed_out || !active(model) {
    Some(board), False ->
      case map_view.beach_bounds(board) {
        Some(#(w, s, e, n)) -> #(True, [
          cmd.MoveCamera(cmd.Fit(w, s, e, n, 40, 13, True)),
        ])
        None -> #(False, [])
      }
    _, _ -> #(model.fitted, [])
  }
}

pub fn trails_loaded(
  model: Model,
  result: Result(trails.Trails, rsvp.Error),
) -> #(Model, List(Cmd)) {
  let next = case result {
    Ok(found) -> Model(..model, trails_file: mdl.TrailsLoaded(found))
    Error(_) -> Model(..model, trails_file: mdl.TrailsMissing)
  }
  #(next, trail_cmds(next))
}
