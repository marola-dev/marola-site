//// The state machine against the real fixture board and catalogs: what a
//// visitor's action changes, and which commands it asks for.

import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import marola/beach.{At, BestHour}
import marola/geo
import marola/language
import marola_client/boards
import marola_client/cmd
import marola_client/latest.{Day}
import marola_client/model as mdl
import marola_client/msg
import marola_client/params
import marola_client/update
import rsvp
import support

fn has(commands: List(cmd.Cmd), wanted: cmd.Cmd) -> Bool {
  list.contains(commands, wanted)
}

fn syncs(commands: List(cmd.Cmd)) -> List(String) {
  list.filter_map(commands, fn(c) {
    case c {
      cmd.SyncMap(text) -> Ok(text)
      _ -> Error(Nil)
    }
  })
}

pub fn init_reads_the_links_it_understands_test() {
  let #(model, commands) =
    update.init(
      support.browser("?layer=water&beaches=0&lang=en&trails=0", ["pt-BR"]),
    )
  assert model.layer == mdl.Water
  assert !model.show_beaches
  assert !model.show_trails
  assert model.loc.language == language.En
  assert commands
    == [cmd.FetchCatalog(language.PtBr), cmd.FetchCatalog(language.En)]
}

pub fn init_ignores_a_layer_whose_button_is_off_test() {
  let #(model, _) = update.init(support.browser("?layer=wind", []))
  assert model.layer == mdl.Off
  let #(model, _) = update.init(support.browser("?layer=nonsense", []))
  assert model.layer == mdl.Off
}

pub fn the_page_waits_for_both_catalogs_then_fetches_the_areas_test() {
  let #(start, _) = update.init(support.browser("", ["en-US"]))
  let #(one, first) =
    update.update(start, msg.CatalogLoaded(language.PtBr, Ok(dict_empty())))
  assert first == []
  assert one.catalogs_pending == 1
  let #(both, second) =
    update.update(one, msg.CatalogLoaded(language.En, Ok(dict_empty())))
  assert both.catalogs_pending == 0
  assert has(second, cmd.FetchAreas)
}

fn dict_empty() {
  dict.new()
}

pub fn the_area_in_the_link_wins_over_the_first_test() {
  let #(start, _) = update.init(support.browser("?area=rio", []))
  let #(model, commands) =
    update.update(
      start,
      msg.AreasLoaded(
        Ok([support.area_named("floripa"), support.area_named("rio")]),
      ),
    )
  assert model.area == Some(support.area_named("rio"))
  assert has(commands, cmd.FetchLatest("rio"))
  assert has(commands, cmd.FetchTrails("rio"))
  assert has(commands, cmd.InitMap(-48.5, -27.6))
  assert model.map == mdl.MapLoading
  assert params.get(model.query, "area") == Some("rio")
}

pub fn no_areas_is_a_status_not_a_crash_test() {
  let #(start, _) = update.init(support.browser("", []))
  let #(model, _) = update.update(start, msg.AreasLoaded(Ok([])))
  assert model.status == mdl.NoAreas
}

pub fn the_newest_day_loads_unless_the_link_names_one_test() {
  let days = [Day("2026-09-06", "a.json"), Day("2026-09-07", "b.json")]
  let #(start, _) = update.init(support.browser("", []))
  let area = msg.AreasLoaded(Ok([support.area_named("floripa")]))
  let #(_, commands) =
    support.run(start, [area, msg.LatestLoaded("floripa", Ok(days))])
  assert has(commands, cmd.FetchBoard("floripa", "2026-09-07", "b.json"))
  let #(linked, _) = update.init(support.browser("?day=2026-09-06", []))
  let #(_, commands) =
    support.run(linked, [area, msg.LatestLoaded("floripa", Ok(days))])
  assert has(commands, cmd.FetchBoard("floripa", "2026-09-06", "a.json"))
}

pub fn an_answer_for_an_area_the_visitor_left_is_dropped_test() {
  let #(model, _) = support.loaded("")
  let stale = support.fixture()
  let #(after, commands) =
    update.update(
      model,
      msg.BoardLoaded("rio", stale.day, "x.json", Ok(boards.Read(stale))),
    )
  assert after == model
  assert commands == []
}

pub fn a_board_newer_than_the_page_is_reported_test() {
  let #(model, _) = support.loaded("")
  let #(after, _) =
    update.update(
      model,
      msg.BoardLoaded(
        "floripa",
        support.fixture().day,
        "x.json",
        Ok(boards.Newer(9)),
      ),
    )
  assert after.status == mdl.TooNew(9)
}

pub fn a_loaded_board_shows_its_beaches_and_fits_the_map_once_test() {
  let #(model, commands) = support.loaded("")
  assert model.status == mdl.Idle
  assert model.hours != []
  assert model.fitted
  assert list.any(commands, fn(c) {
    case c {
      cmd.MoveCamera(cmd.Fit(..)) -> True
      _ -> False
    }
  })
  let assert [text] = syncs(commands)
  assert string.contains(text, "Praia da Joaquina")
  assert string.contains(text, "Praia Brava")
}

pub fn a_beach_in_the_link_opens_its_card_test() {
  let #(model, _) = support.loaded("?beach=Praia%20Brava")
  assert model.selected == Some("Praia Brava")
  let #(model, _) = support.loaded("?beach=Nowhere")
  assert model.selected == None
}

pub fn picking_and_closing_a_beach_keeps_the_link_in_step_test() {
  let #(model, _) = support.loaded("")
  let #(picked, commands) =
    update.update(model, msg.BeachPicked("Praia Brava", True))
  assert picked.selected == Some("Praia Brava")
  assert has(commands, cmd.ReplaceUrl("/", params.to_string(picked.query)))
  assert params.get(picked.query, "beach") == Some("Praia Brava")
  let #(closed, _) = update.update(picked, msg.CardClosed)
  assert closed.selected == None
  assert params.get(closed.query, "beach") == None
}

pub fn the_slider_moves_between_best_hour_and_a_clock_hour_test() {
  let #(model, _) = support.loaded("")
  let #(moved, _) = update.update(model, msg.HourMoved(0))
  let assert Ok(first) = list.first(model.hours)
  assert moved.selection == At(first)
  let #(back, _) = update.update(moved, msg.HourMoved(-1))
  assert back.selection == BestHour
}

pub fn a_layer_button_that_is_off_does_nothing_test() {
  let #(model, _) = support.loaded("")
  let #(after, commands) = update.update(model, msg.LayerPressed(mdl.Wind))
  assert after == model
  assert commands == []
}

pub fn pressing_the_water_layer_twice_turns_it_off_test() {
  let #(model, _) = support.loaded("")
  let #(on, _) = update.update(model, msg.LayerPressed(mdl.Water))
  assert on.layer == mdl.Water
  assert params.get(on.query, "layer") == Some("water")
  let #(off, _) = update.update(on, msg.LayerPressed(mdl.Water))
  assert off.layer == mdl.Off
}

pub fn the_beach_list_and_the_trail_panel_never_share_the_edge_test() {
  let #(model, _) = support.loaded("")
  let #(list_open, _) = update.update(model, msg.ListToggled)
  assert list_open.panel == mdl.BeachList
  let #(trails_open, _) = update.update(list_open, msg.TrailPanelToggled)
  assert trails_open.panel == mdl.TrailList
  let #(closed, _) = update.update(trails_open, msg.TrailPanelToggled)
  assert closed.panel == mdl.Closed
}

pub fn a_style_error_before_the_map_loads_opens_the_list_test() {
  let #(model, _) = support.loaded("")
  let #(failed, _) = update.update(model, msg.MapEvent("error", "style"))
  assert failed.map == mdl.MapFailed("map.failed")
  assert failed.panel == mdl.BeachList
}

pub fn an_error_after_the_map_is_ready_is_ignored_test() {
  let #(model, _) = support.loaded("")
  let #(ready, _) = update.update(model, msg.MapEvent("ready", ""))
  let #(after, _) = update.update(ready, msg.MapEvent("error", "tile"))
  assert after.map == mdl.MapReady
  assert after.panel == mdl.Closed
}

pub fn a_click_on_a_dot_picks_the_beach_without_panning_test() {
  let #(model, _) = support.loaded("")
  let #(picked, commands) =
    update.update(model, msg.MapEvent("beach", "Praia Brava"))
  assert picked.selected == Some("Praia Brava")
  assert !list.any(commands, fn(c) {
    case c {
      cmd.MoveCamera(cmd.Pan(..)) -> True
      _ -> False
    }
  })
}

pub fn picking_a_language_stores_it_and_retitles_the_page_test() {
  let #(model, _) = support.loaded("")
  let #(after, commands) = update.update(model, msg.LanguagePicked(language.En))
  assert after.loc.language == language.En
  assert params.get(after.query, "lang") == Some("en")
  assert has(commands, cmd.StoreLanguage(language.En))
  assert has(
    commands,
    cmd.SetDocument("en", "marola: sea conditions at every beach"),
  )
  assert syncs(commands) != []
}

pub fn the_same_language_again_changes_nothing_test() {
  let #(model, _) = support.loaded("")
  let #(after, commands) =
    update.update(model, msg.LanguagePicked(language.PtBr))
  assert after == model
  assert commands == []
}

pub fn a_picked_route_closes_the_beach_card_test() {
  let #(model, _) = support.loaded("?beach=Praia%20Brava")
  let #(with_trails, _) =
    update.update(
      model,
      msg.TrailsFileLoaded("floripa", Ok(support.trails_file("floripa"))),
    )
  let #(picked, _) = update.update(with_trails, msg.TrailChosen(0, True))
  assert picked.trail_selected == Some(0)
  assert picked.selected == None
  assert params.get(picked.query, "beach") == None
}

pub fn a_route_id_that_does_not_exist_changes_nothing_test() {
  let #(model, _) = support.loaded("")
  let #(with_trails, _) =
    update.update(
      model,
      msg.TrailsFileLoaded("floripa", Ok(support.trails_file("floripa"))),
    )
  let #(after, commands) =
    update.update(with_trails, msg.TrailChosen(99_999, True))
  assert after == with_trails
  assert commands == []
}

pub fn a_missing_trail_file_falls_back_to_the_board_test() {
  let #(model, _) = support.loaded("")
  let #(after, _) =
    update.update(
      model,
      msg.TrailsFileLoaded("floripa", Error(rsvp.NetworkError)),
    )
  assert after.trails_file == mdl.TrailsMissing
  assert mdl.trails(after) != None
}

pub fn the_location_answer_ranks_by_distance_and_opens_the_list_test() {
  let #(model, _) = support.loaded("")
  let #(after, _) =
    update.update(model, msg.Located(Ok(geo.Point(-27.6, -48.5))))
  assert after.here == Some(geo.Point(-27.6, -48.5))
  assert after.panel == mdl.BeachList
}
