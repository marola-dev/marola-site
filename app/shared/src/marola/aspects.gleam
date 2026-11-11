//// The aspect cells of a beach tooltip and card: wind, water, waves,
//// jellyfish, whales, water quality and facilities. It is app.js
//// `aspectsHtml` as data: the renderer adds icons and escapes the text.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import marola/beach.{type Beach, type Facilities}
import marola/fmt
import marola/geo
import marola/hour.{type Hour, type Shown}
import marola/i18n.{type Locale}
import marola/level.{type Level}
import marola/water
import marola/wind

pub type Facility {
  Facility(key: String, text: String)
}

pub type Cell {
  Wind(text: String)
  WaterTemp(text: String)
  Waves(text: String)
  Jellyfish(text: String)
  Whales(text: String)
  Quality(text: String, unfit: Bool, dot_class: String)
  FacilityCounts(List(Facility))
}

/// `cells` is empty when the beach is dark at that hour.
pub type Aspects {
  Aspects(head: String, cells: List(Cell))
}

/// The cell's reading as one line of text.
pub fn cell_text(cell: Cell) -> String {
  case cell {
    Wind(text)
    | WaterTemp(text)
    | Waves(text)
    | Jellyfish(text)
    | Whales(text) -> text
    Quality(text, _, _) -> text
    FacilityCounts(parts) ->
      list.map(parts, fn(p) { p.text }) |> string.join(" · ")
  }
}

pub fn of(beach: Beach, shown: Option(Shown), loc: Locale) -> Aspects {
  let head = beach.name <> " · " <> head_text(shown, loc)
  case beach.hour_entry(beach, shown), shown {
    Some(entry), Some(s) -> Aspects(head, cells(beach, entry, s, loc))
    _, _ -> Aspects(head, [])
  }
}

fn head_text(shown: Option(Shown), loc: Locale) -> String {
  case shown {
    Some(s) ->
      i18n.t(loc, "tip.at", [
        i18n.number_arg("score", int.to_float(s.score)),
        i18n.arg("h", s.h),
      ])
    None -> i18n.t(loc, "tip.dark", [])
  }
}

fn cells(beach: Beach, e: Hour, s: Shown, loc: Locale) -> List(Cell) {
  let facilities = case facility_parts(beach.facilities, loc) {
    [] -> []
    parts -> [FacilityCounts(parts)]
  }
  list.flatten([
    [
      Wind(wind_text(beach, e, s, loc)),
      WaterTemp(
        i18n.t(loc, "cell.water", [
          i18n.arg("v", fmt.value(loc, e.sea_temp_c, " °C", 1)),
        ]),
      ),
      Waves(
        fmt.waves(loc, e.wave_m, case s.best {
          True -> beach.sea.period_s
          False -> None
        }),
      ),
      Jellyfish(
        i18n.t(loc, "cell.jellyfish", [
          i18n.arg("level", level_word(loc, e.jellyfish)),
        ]),
      ),
      Whales(whales_text(beach, e, loc)),
      Quality(
        water.summary_text(beach.water, loc),
        beach.water.unfit,
        water.dot_class(beach.water),
      ),
    ],
    facilities,
  ])
}

fn level_word(loc: Locale, level: Level) -> String {
  i18n.word(loc, "lvl.", level.to_string(level))
}

fn wind_text(beach: Beach, e: Hour, s: Shown, loc: Locale) -> String {
  let kmh = fmt.value(loc, e.wind_kmh, " km/h", 0)
  // An older board has no band: the number only, no word.
  let band_word = case option.map(e.wind_level, wind.to_string) {
    Some("") | None -> None
    Some(raw) -> Some(i18n.word(loc, "wind.", raw))
  }
  let reading = case band_word {
    Some(word) -> word <> ", " <> kmh
    None -> i18n.t(loc, "cell.wind", [i18n.arg("v", kmh)])
  }
  case s.best, beach.sea.wind_dir_deg {
    True, Some(deg) ->
      reading <> " " <> i18n.word(loc, "dir.", geo.compass_key(deg))
    _, _ -> reading
  }
}

fn whales_text(beach: Beach, e: Hour, loc: Locale) -> String {
  let peak = case beach.whales.peak {
    Some(p) if p != "" && p != e.h -> True
    _ -> False
  }
  i18n.t(loc, "cell.whales", [
    i18n.arg("level", level_word(loc, e.whales)),
    i18n.arg("best", yes_no(peak)),
    i18n.arg("peak", option.unwrap(beach.whales.peak, "")),
  ])
}

fn facility_parts(
  facilities: Option(Facilities),
  loc: Locale,
) -> List(Facility) {
  case facilities {
    None -> []
    Some(f) ->
      [
        #("parking", f.parking),
        #("toilets", f.toilets),
        #("shower", f.shower),
        #("lifeguard", f.lifeguard),
      ]
      |> list.filter_map(fn(entry) {
        case entry.1 {
          None -> Error(Nil)
          Some(n) ->
            Ok(Facility(
              entry.0,
              i18n.t(loc, "fac." <> entry.0, [
                i18n.number_arg("n", int.to_float(n)),
              ]),
            ))
        }
      })
  }
}

pub fn yes_no(flag: Bool) -> String {
  case flag {
    True -> "yes"
    False -> "no"
  }
}
