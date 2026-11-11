//// The part of `update` that answers the visitor: the slider, the picked
//// beach, the layers, the panels, the language and the map's own events.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import marola/beach.{type Beach, At, BestHour}
import marola/i18n.{Locale}
import marola/language.{type Language}
import marola/trails
import marola_client/cmd.{type Cmd}
import marola_client/config
import marola_client/map_view
import marola_client/model.{type Model, Model} as mdl
import marola_client/msg
import marola_client/update/support.{
  active, delete_param, flow_cmds, set_param, sync, trail_cmds, url,
}

pub fn hour_moved(model: Model, index: Int) -> #(Model, List(Cmd)) {
  let selection = case list.drop(model.hours, index) |> list.first {
    Ok(h) if index >= 0 -> At(h)
    _ -> BestHour
  }
  let next = Model(..model, selection:)
  sync(next, flow_cmds(next))
}

pub fn beach_picked(
  model: Model,
  name: String,
  pan: Bool,
) -> #(Model, List(Cmd)) {
  let next =
    Model(..model, selected: Some(name), trail_selected: None)
    |> set_param("beach", name)
  let camera = case pan, active(next), find_beach(next, name) {
    True, True, Some(b) -> [cmd.MoveCamera(cmd.Pan(b.lon, b.lat))]
    _, _, _ -> []
  }
  sync(next, [url(next), ..camera])
}

fn find_beach(model: Model, name: String) -> Option(Beach) {
  case model.board {
    None -> None
    Some(board) ->
      list.find(board.beaches, fn(b) { b.name == name }) |> option.from_result
  }
}

/// The card of a beach or of a trail closes; a click on the empty map does the same.
pub fn close_cards(model: Model) -> #(Model, List(Cmd)) {
  case model.selected, model.trail_selected {
    None, None -> #(model, [])
    _, _ -> {
      let next =
        Model(..model, selected: None, trail_selected: None)
        |> delete_param("beach")
      sync(next, [url(next)])
    }
  }
}

pub fn layer_pressed(model: Model, layer: mdl.Layer) -> #(Model, List(Cmd)) {
  case mdl.layer_enabled(layer) {
    False -> #(model, [])
    True -> {
      // A pressed layer button turns its layer off again.
      let picked = case layer == model.layer {
        True -> mdl.Off
        False -> layer
      }
      let next =
        Model(..model, layer: picked)
        |> set_param("layer", mdl.layer_key(picked))
      let #(next, camera) = zoom_for_layer(next)
      sync(next, list.flatten([camera, flow_cmds(next), [url(next)]]))
    }
  }
}

/// El Nino needs the Pacific in view, below the area's own minimum zoom.
fn zoom_for_layer(model: Model) -> #(Model, List(Cmd)) {
  let nino = model.layer == mdl.Elnino
  case nino == model.zoomed_out {
    True -> #(model, [])
    False -> {
      let next = Model(..model, zoomed_out: nino)
      let min =
        cmd.MoveCamera(
          cmd.MinZoom(case nino {
            True -> 0
            False -> config.area_min_zoom
          }),
        )
      let view = case nino, next.board |> option.then(map_view.beach_bounds) {
        True, _ -> [cmd.MoveCamera(cmd.Pacific(next.reduced_motion))]
        False, Some(#(w, s, e, n)) -> [
          cmd.MoveCamera(cmd.Fit(w, s, e, n, 40, 13, next.reduced_motion)),
        ]
        False, None -> []
      }
      #(next, [min, ..view])
    }
  }
}

pub fn toggled(model: Model, key: String, on: Bool) -> #(Model, List(Cmd)) {
  let flag = case on {
    True -> "1"
    False -> "0"
  }
  let next = case key {
    "beaches" -> Model(..model, show_beaches: on)
    _ -> Model(..model, show_trails: on)
  }
  let next = set_param(next, key, flag)
  sync(next, [url(next)])
}

pub fn panel_toggled(model: Model, panel: mdl.Panel) -> #(Model, List(Cmd)) {
  let next = case model.panel == panel {
    True -> mdl.Closed
    False -> panel
  }
  #(Model(..model, panel: next), [])
}

pub fn trail_chosen(model: Model, id: Int, fit: Bool) -> #(Model, List(Cmd)) {
  case mdl.trails(model) |> option.map(trails.route_at(_, id)) {
    Some(Ok(route)) -> {
      let next =
        Model(..model, trail_selected: Some(id), selected: None)
        |> delete_param("beach")
      let camera = case fit, active(next), route_bounds(route) {
        True, True, Some(#(w, s, e, n)) -> [
          cmd.MoveCamera(cmd.Fit(w, s, e, n, 60, 15, next.reduced_motion)),
        ]
        _, _, _ -> []
      }
      sync(next, [url(next), ..camera])
    }
    _ -> #(model, [])
  }
}

fn route_bounds(route: trails.Route) -> Option(#(Float, Float, Float, Float)) {
  case list.flatten(trails.drawable_lines(route)) {
    [] -> None
    [first, ..rest] ->
      Some(
        list.fold(rest, #(first.lon, first.lat, first.lon, first.lat), fn(b, p) {
          #(
            float.min(b.0, p.lon),
            float.min(b.1, p.lat),
            float.max(b.2, p.lon),
            float.max(b.3, p.lat),
          )
        }),
      )
  }
}

pub fn near_pressed(model: Model) -> #(Model, List(Cmd)) {
  case model.here {
    Some(_) -> sync(Model(..model, here: None), [])
    None -> #(model, [cmd.Locate])
  }
}

pub fn fold_toggled(model: Model, fold: msg.Fold) -> Model {
  case fold {
    msg.LoreFold -> Model(..model, lore_open: !model.lore_open)
    msg.BlurbFold -> Model(..model, blurb_open: !model.blurb_open)
  }
}

pub fn sos_closed(model: Model) -> #(Model, List(Cmd)) {
  case model.sos_open {
    True -> #(Model(..model, sos_open: False), [cmd.Focus("sos")])
    False -> #(model, [])
  }
}

pub fn language_picked(
  model: Model,
  language: Language,
) -> #(Model, List(Cmd)) {
  case language == model.loc.language {
    True -> #(model, [])
    False -> {
      let next =
        Model(..model, loc: Locale(..model.loc, language:))
        |> set_param("lang", language.tag(language))
      let #(next, cmds) = sync(next, trail_cmds(next))
      #(next, [
        cmd.StoreLanguage(language),
        url(next),
        cmd.SetDocument(
          language.tag(language),
          i18n.t(next.loc, "title.map", []),
        ),
        ..cmds
      ])
    }
  }
}

pub fn map_event(
  model: Model,
  kind: String,
  arg: String,
) -> #(Model, List(Cmd)) {
  case kind, int.parse(arg) {
    "ready", _ -> #(Model(..model, map: mdl.MapReady), [])
    "error", _ ->
      // An error before the map loads is the style or its sprites: the list
      // carries the page, and says why there is no map.
      case model.map {
        mdl.MapLoading -> #(
          Model(..model, map: mdl.MapFailed("map.failed"), panel: mdl.BeachList),
          [],
        )
        _ -> #(model, [])
      }
    "click", _ -> close_cards(model)
    "beach", _ -> beach_picked(model, arg, False)
    "trail", Ok(id) -> trail_chosen(model, id, False)
    _, _ -> #(model, [])
  }
}
