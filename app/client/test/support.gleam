//// Shared helpers of the client tests: the real catalogs, the fixture board
//// and the trail files. The tests run from `app/client`.

import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import marola/area.{type Area, Area}
import marola/board.{type Board}
import marola/i18n.{Locale}
import marola/language.{type Language}
import marola/trails.{type Trails}
import marola_client/boards
import marola_client/cmd.{type Cmd}
import marola_client/latest.{Day}
import marola_client/model.{type Model, Model}
import marola_client/msg.{type Msg}
import marola_client/params
import marola_client/update

@external(javascript, "./client_test_ffi.mjs", "read_file")
fn read_file(path: String) -> Result(String, String)

pub fn read(path: String) -> String {
  case read_file(path) {
    Ok(text) -> text
    Error(reason) -> panic as { "cannot read " <> path <> ": " <> reason }
  }
}

pub fn parse(text: String, decoder: Decoder(a)) -> a {
  case json.parse(text, decoder) {
    Ok(value) -> value
    Error(error) -> panic as { "bad JSON: " <> string.inspect(error) }
  }
}

pub fn fixture() -> Board {
  parse(read("../../site/fixtures/board.json"), board.decoder())
}

pub fn trails_file(area: String) -> Trails {
  parse(read("static/data/trails/" <> area <> ".json"), trails.decoder())
}

fn messages(tag: String) -> Dict(String, String) {
  parse(read("../../site/i18n/" <> tag <> ".json"), i18n.messages_decoder())
}

pub fn browser(search: String, languages: List(String)) -> update.Env {
  update.Env(
    path: "/",
    query: params.parse(search),
    languages:,
    stored_language: None,
    reduced_motion: False,
  )
}

pub fn area_named(id: String) -> Area {
  Area(id:, name: "Area " <> id, lat: -27.6, lon: -48.5)
}

/// Feeds each message to `update`, keeping the commands of the last one.
pub fn run(model: Model, messages: List(Msg)) -> #(Model, List(Cmd)) {
  list.fold(messages, #(model, []), fn(acc, message) {
    update.update(acc.0, message)
  })
}

/// A page that has loaded its catalogs, an area, a day and the fixture board.
pub fn loaded(search: String) -> #(Model, List(Cmd)) {
  let #(start, _) = update.init(browser(search, ["pt-BR"]))
  let b = fixture()
  run(start, [
    msg.CatalogLoaded(language.PtBr, Ok(messages("pt-BR"))),
    msg.CatalogLoaded(language.En, Ok(messages("en"))),
    msg.AreasLoaded(Ok([area_named("floripa"), area_named("rio")])),
    msg.LatestLoaded("floripa", Ok([Day(b.day, b.day <> ".json")])),
    msg.BoardLoaded("floripa", b.day, b.day <> ".json", Ok(boards.Read(b))),
  ])
}

pub fn in_language(model: Model, language: Language) -> Model {
  Model(..model, loc: Locale(..model.loc, language:))
}
