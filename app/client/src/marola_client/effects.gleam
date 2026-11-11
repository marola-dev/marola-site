//// The one place that carries out what `update` asks: requests through
//// `rsvp`, and the browser and the map through the two FFI files. Their
//// arguments are strings, numbers and functions, so no Gleam list crosses.

import gleam/json
import gleam/list
import lustre/effect.{type Effect}
import marola/area
import marola/geo
import marola/i18n
import marola/language
import marola/trails
import marola_client/boards
import marola_client/cmd.{type Camera, type Cmd}
import marola_client/config
import marola_client/latest
import marola_client/msg.{type Msg}
import rsvp

@external(javascript, "./maplibre_ffi.mjs", "initMap")
fn init_map(config: String, emit: fn(String, String) -> Nil) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "syncMap")
fn sync_map(json: String) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "setTrails")
fn set_trails(geojson: String) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "setFlow")
fn set_flow(json: String) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "camera")
fn camera(json: String) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "locate")
fn locate(ok: fn(Float, Float) -> Nil, failed: fn(String) -> Nil) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "playSound")
fn play_sound(on: Bool, url: String, failed: fn() -> Nil) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "storeLanguage")
fn store_language(tag: String) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "replaceUrl")
fn replace_url(path: String, query: String) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "setDocument")
fn set_document(language: String, title: String) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "focusId")
fn focus_id(id: String) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "alertText")
fn alert_text(text: String) -> Nil

@external(javascript, "./maplibre_ffi.mjs", "readEnv")
pub fn read_env() -> String

@external(javascript, "./maplibre_ffi.mjs", "readLanguage")
pub fn read_language() -> String

pub fn run(cmds: List(Cmd)) -> Effect(Msg) {
  effect.batch(list.map(cmds, one))
}

fn call(work: fn() -> Nil) -> Effect(Msg) {
  effect.from(fn(_dispatch) { work() })
}

fn one(command: Cmd) -> Effect(Msg) {
  case command {
    cmd.FetchCatalog(language) ->
      // rsvp reads a URL that starts with neither "./" nor "/" as an absolute
      // one, and fails it, so every page-relative URL here starts with "./".
      rsvp.get(
        "./i18n/" <> language.tag(language) <> ".json",
        rsvp.expect_json(i18n.messages_decoder(), msg.CatalogLoaded(language, _)),
      )
    cmd.FetchAreas ->
      rsvp.get(
        "./data/areas.json",
        rsvp.expect_json(area.list_decoder(), msg.AreasLoaded),
      )
    cmd.FetchLatest(id) ->
      rsvp.get(
        "./data/" <> id <> "/latest.json",
        rsvp.expect_json(latest.decoder(), msg.LatestLoaded(id, _)),
      )
    cmd.FetchBoard(id, day, file) ->
      rsvp.get(
        "./data/" <> id <> "/" <> file,
        rsvp.expect_json(boards.decoder(), msg.BoardLoaded(id, day, file, _)),
      )
    cmd.FetchTrails(id) ->
      rsvp.get(
        "./data/trails/" <> id <> ".json",
        rsvp.expect_json(trails.decoder(), msg.TrailsFileLoaded(id, _)),
      )
    cmd.ReplaceUrl(path, query) -> call(fn() { replace_url(path, query) })
    cmd.SetDocument(language, title) ->
      call(fn() { set_document(language, title) })
    cmd.StoreLanguage(language) ->
      call(fn() { store_language(language.tag(language)) })
    cmd.InitMap(lon, lat) ->
      effect.from(fn(dispatch) {
        init_map(map_config(lon, lat), fn(kind, arg) {
          dispatch(msg.MapEvent(kind, arg))
        })
      })
    cmd.SyncMap(text) -> call(fn() { sync_map(text) })
    cmd.SetTrails(text) -> call(fn() { set_trails(text) })
    cmd.SetFlow(text) -> call(fn() { set_flow(text) })
    cmd.MoveCamera(view) -> call(fn() { camera(camera_json(view)) })
    cmd.Locate ->
      effect.from(fn(dispatch) {
        locate(
          fn(lat, lon) { dispatch(msg.Located(Ok(geo.Point(lat, lon)))) },
          fn(why) { dispatch(msg.Located(Error(why))) },
        )
      })
    cmd.Alert(text) -> call(fn() { alert_text(text) })
    cmd.Sound(on) ->
      effect.from(fn(dispatch) {
        play_sound(on, config.sound_url, fn() { dispatch(msg.SoundFailed) })
      })
    cmd.Focus(id) -> call(fn() { focus_id(id) })
  }
}

/// What `maplibre_ffi.mjs` needs to build the map, as one JSON text.
pub fn map_config(lon: Float, lat: Float) -> String {
  json.object([
    #("lon", json.float(lon)),
    #("lat", json.float(lat)),
    #("zoom", json.float(config.area_zoom)),
    #("minZoom", json.int(config.area_min_zoom)),
    #("maxZoom", json.int(config.max_zoom)),
    #("style", json.string(config.style_url)),
    #("attributions", json.array(config.attributions, json.string)),
    #("module", json.string(config.maplibre_module)),
    #("worker", json.string(config.maplibre_worker)),
  ])
  |> json.to_string
}

pub fn camera_json(view: Camera) -> String {
  case view {
    cmd.Jump(lon, lat, zoom) ->
      json.object([
        #("kind", json.string("jump")),
        #("lon", json.float(lon)),
        #("lat", json.float(lat)),
        #("zoom", json.float(zoom)),
      ])
    cmd.Pan(lon, lat) ->
      json.object([
        #("kind", json.string("pan")),
        #("lon", json.float(lon)),
        #("lat", json.float(lat)),
      ])
    cmd.Fit(west, south, east, north, padding, max_zoom, instant) ->
      json.object([
        #("kind", json.string("fit")),
        #("west", json.float(west)),
        #("south", json.float(south)),
        #("east", json.float(east)),
        #("north", json.float(north)),
        #("padding", json.int(padding)),
        #("max_zoom", json.int(max_zoom)),
        #("instant", json.bool(instant)),
      ])
    cmd.Pacific(instant) ->
      json.object([
        #("kind", json.string("pacific")),
        #("instant", json.bool(instant)),
      ])
    cmd.MinZoom(zoom) ->
      json.object([
        #("kind", json.string("minzoom")),
        #("zoom", json.int(zoom)),
      ])
  }
  |> json.to_string
}
