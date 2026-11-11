//// What every part of `update` shares: the query string, the commands that
//// bring the map up to date, and the way a failed request reads in the footer.

import gleam/int
import gleam/option.{type Option, Some}
import marola_client/cmd.{type Cmd}
import marola_client/flow_data
import marola_client/map_view
import marola_client/model.{type Model, Model} as mdl
import marola_client/params
import marola_client/trail_geo
import rsvp

pub fn active(model: Model) -> Bool {
  model.map == mdl.MapLoading || model.map == mdl.MapReady
}

pub fn set_param(model: Model, key: String, value: String) -> Model {
  Model(..model, query: params.set(model.query, key, value))
}

pub fn delete_param(model: Model, key: String) -> Model {
  Model(..model, query: params.delete(model.query, key))
}

pub fn url(model: Model) -> Cmd {
  cmd.ReplaceUrl(model.path, params.to_string(model.query))
}

/// The markers, raster and visibility, when there is a map to hold them.
pub fn sync(model: Model, more: List(Cmd)) -> #(Model, List(Cmd)) {
  case active(model) {
    True -> #(model, [cmd.SyncMap(map_view.sync_json(model)), ..more])
    False -> #(model, more)
  }
}

pub fn trail_cmds(model: Model) -> List(Cmd) {
  case active(model) {
    True -> [cmd.SetTrails(trail_geo.collection(mdl.trails(model), model.loc))]
    False -> []
  }
}

pub fn flow_cmds(model: Model) -> List(Cmd) {
  case active(model) {
    True -> [cmd.SetFlow(flow_data.json(model))]
    False -> []
  }
}

/// The answer to a request for an area the visitor has left is not theirs any more.
pub fn guard_area(
  model: Model,
  area: String,
  then: fn() -> #(Model, List(Cmd)),
) -> #(Model, List(Cmd)) {
  case current_area(model) == Some(area) {
    True -> then()
    False -> #(model, [])
  }
}

pub fn guard_day(
  model: Model,
  area: String,
  day: String,
  then: fn() -> #(Model, List(Cmd)),
) -> #(Model, List(Cmd)) {
  case current_area(model) == Some(area) && model.day == Some(day) {
    True -> then()
    False -> #(model, [])
  }
}

fn current_area(model: Model) -> Option(String) {
  option.map(model.area, fn(a) { a.id })
}

/// What the footer says of a failed request: the status and the path, as the
/// old page's `fetchJson` did.
pub fn describe(error: rsvp.Error, path: String) -> #(String, Bool) {
  case error {
    rsvp.HttpError(response) -> #(
      int.to_string(response.status) <> " " <> path,
      response.status == 404,
    )
    rsvp.NetworkError -> #("network error " <> path, False)
    rsvp.BadUrl(_) -> #("bad address " <> path, False)
    _ -> #("bad data " <> path, False)
  }
}

pub fn fail(
  model: Model,
  error: rsvp.Error,
  path: String,
) -> #(Model, List(Cmd)) {
  let #(text, missing) = describe(error, path)
  #(Model(..model, status: mdl.Failed(text, missing)), [])
}
