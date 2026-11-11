//// The old app.js beach functions against golden.json.

import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import marola/aspects
import marola/beach
import marola/board
import marola/decoders
import marola/geo
import marola/rank
import marola/water
import support

fn why(section: String, detail: String) -> String {
  "golden " <> section <> ": " <> detail
}

pub fn haversine_test() {
  let point = {
    use lat <- decode.field("lat", decoders.number())
    use lon <- decode.field("lon", decoders.number())
    decode.success(geo.Point(lat, lon))
  }
  let entry = {
    use a <- decode.field("a", point)
    use b <- decode.field("b", point)
    use km <- decode.field("km", decoders.number())
    decode.success(#(a, b, km))
  }
  use #(a, b, km) <- list.each(support.golden("haversine", entry))
  // sin and asin come from two different libms, so the last digits may differ
  assert support.close(geo.haversine_km(a, b), km, 1.0e-12)
    as why("haversine", string.inspect(#(a, b)))
}

pub fn shown_and_hour_entry_test() {
  let shown = {
    use h <- decode.field("h", decode.string)
    use score <- decode.field("score", decode.int)
    use notes <- decode.field("notes", decode.list(decode.string))
    use best <- decode.optional_field("best", False, decode.bool)
    decode.success(#(h, score, notes, best))
  }
  let entry = {
    use variant <- decode.field("variant", decode.string)
    use selection <- decode.field("selection", decode.optional(decode.string))
    use expected <- decode.field("shown", decode.optional(shown))
    use entry_h <- decode.field("entry_h", decode.optional(decode.string))
    decode.success(#(variant, selection, expected, entry_h))
  }
  use #(variant, selection, expected, entry_h) <- list.each(support.golden(
    "shown",
    entry,
  ))
  let b = support.beach_named(variant)
  let s = beach.shown(b, support.selection(selection))
  let got = option.map(s, fn(s) { #(s.h, s.score, s.notes, s.best) })
  assert got == expected as why("shown", variant)
  let e = beach.hour_entry(b, s) |> option.map(fn(e) { e.h })
  assert e == entry_h as why("hour_entry", variant)
}

type Mark {
  Mark(cls: String, dot: Option(String))
}

pub fn aspects_test() {
  let mark =
    decode.optional({
      use cls <- decode.field("cls", decode.string)
      use dot <- decode.field("dot", decode.optional(decode.string))
      decode.success(Mark(cls, dot))
    })
  let entry = {
    use lang <- decode.field("lang", support.lang_decoder())
    use variant <- decode.field("variant", decode.string)
    use selection <- decode.field("selection", decode.optional(decode.string))
    use head <- decode.field("head", decode.string)
    use cells <- decode.field("cells", decode.list(decode.string))
    use marks <- decode.field("marks", decode.list(mark))
    decode.success(#(lang, variant, selection, head, cells, marks))
  }
  use #(lang, variant, selection, head, cells, marks) <- list.each(
    support.golden("aspects", entry),
  )
  let b = support.beach_named(variant)
  let shown = beach.shown(b, support.selection(selection))
  let got = aspects.of(b, shown, support.locale(lang))
  let label = string.inspect(#(lang, variant, selection))
  assert got.head == head as why("aspects head", label)
  assert list.map(got.cells, aspects.cell_text) == cells
    as why("aspects cells", label)
  // The water cell is the only one the old markup gave a class and a dot.
  let quality =
    list.find_map(marks, fn(m) {
      case m {
        Some(Mark(cls, Some(dot))) -> Ok(#(string.contains(cls, "unfit"), dot))
        _ -> Error(Nil)
      }
    })
  let got_quality =
    list.find_map(got.cells, fn(c) {
      case c {
        aspects.Quality(_, unfit, dot) -> Ok(#(unfit, dot))
        _ -> Error(Nil)
      }
    })
  assert got_quality == quality as why("aspects water cell", label)
}

pub fn is_past_test() {
  let entry = {
    use day <- decode.field("day", decode.string)
    use today <- decode.field("today", decode.string)
    use generated_at <- decode.field("generated_at", decode.string)
    use h <- decode.field("h", decode.string)
    use out <- decode.field("out", decode.bool)
    decode.success(#(day, today, generated_at, h, out))
  }
  use #(day, today, generated_at, h, out) <- list.each(support.golden(
    "is_past",
    entry,
  ))
  let b =
    board.Board(
      schema: 2,
      area: "x",
      day:,
      today:,
      generated_at:,
      sources: board.Sources("", "", None),
      lore: None,
      beaches: [],
      trails: [],
    )
  assert board.is_past(b, h) == out
    as why("is_past", string.inspect(#(day, today, h)))
}

pub fn ranked_test() {
  let point = {
    use lat <- decode.field("lat", decoders.number())
    use lon <- decode.field("lon", decoders.number())
    decode.success(geo.Point(lat, lon))
  }
  let entry = {
    use variants <- decode.field("variants", decode.list(decode.string))
    use hours <- decode.field("hours", decode.list(decode.string))
    use index <- decode.field("index", decode.optional(decode.int))
    use here <- decode.field("here", decode.optional(point))
    use names <- decode.field("names", decode.list(decode.string))
    use km <- decode.field(
      "km",
      decode.optional(decode.list(decoders.number())),
    )
    decode.success(#(variants, hours, index, here, names, km))
  }
  use #(variants, hours, index, here, names, km) <- list.each(support.golden(
    "ranked",
    entry,
  ))
  let beaches = list.map(variants, support.beach_named)
  let selection = case index {
    None -> beach.BestHour
    Some(i) ->
      support.selection(list.drop(hours, i) |> list.first |> option.from_result)
  }
  let label = string.inspect(#(index, here))
  case here {
    None -> {
      let got = rank.by_score(beaches, selection) |> list.map(fn(b) { b.name })
      assert got == names as why("ranked by score", label)
    }
    Some(here) -> {
      let got = rank.by_distance(beaches, here)
      assert list.map(got, fn(pair) { { pair.0 }.name }) == names
        as why("ranked by distance", label)
      let assert Some(expected_km) = km
      assert support.all_close(
        list.map(got, fn(pair) { pair.1 }),
        expected_km,
        1.0e-12,
      )
        as why("ranked km", label)
    }
  }
}

pub fn ranking_leaves_the_board_alone_test() {
  let beaches = list.map(["joaquina", "brava"], support.beach_named)
  let _ = rank.by_distance(beaches, geo.Point(-27.6, -48.48))
  let _ = rank.by_score(beaches, beach.BestHour)
  assert beaches == list.map(["joaquina", "brava"], support.beach_named)
  assert water.has_no_data(water.Water("no data", False, None, None, []))
}
