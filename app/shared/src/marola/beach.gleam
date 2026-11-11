//// A beach: where it is, how it scores hour by hour, its water, sea and facilities.

import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/option.{type Option, None, Some}
import marola/decoders
import marola/hour.{type Best, type Hour, type Shown, Shown}
import marola/level.{type Level}
import marola/water.{type Water}

pub type Tide {
  Tide(time: String, m: Float, high: Bool)
}

/// Conditions at the best hour.
pub type Sea {
  Sea(
    temp_c: Option(Float),
    wave_m: Option(Float),
    period_s: Option(Float),
    wave_dir_deg: Option(Float),
    swell_m: Option(Float),
    swell_period_s: Option(Float),
    current_kmh: Option(Float),
    wind_kmh: Option(Float),
    wind_dir_deg: Option(Float),
    air_temp_c: Option(Float),
    uv: Option(Float),
    rain_pct: Option(Float),
  )
}

pub type Whales {
  Whales(now: Level, peak: Option(String), season: Bool)
}

/// OSM amenity counts within 300 m. An absent key means no data, never zero.
pub type Facilities {
  Facilities(
    parking: Option(Int),
    toilets: Option(Int),
    shower: Option(Int),
    lifeguard: Option(Int),
  )
}

pub type Beach {
  Beach(
    name: String,
    lat: Float,
    lon: Float,
    best: Best,
    hours: List(Hour),
    water: Water,
    tides: List(Tide),
    sea: Sea,
    jellyfish: Level,
    whales: Whales,
    facilities: Option(Facilities),
  )
}

/// The slider's position: each beach at its own best hour, or one clock hour.
pub type Selection {
  BestHour
  At(String)
}

/// The shape a beach shows for the slider position. `None` means the beach is
/// dark at that hour.
pub fn shown(beach: Beach, selection: Selection) -> Option(Shown) {
  case selection {
    BestHour ->
      Some(Shown(
        h: beach.best.hour,
        score: beach.best.score,
        notes: beach.best.notes,
        note_codes: beach.best.note_codes,
        best: True,
      ))
    At(h) ->
      list.find(beach.hours, fn(x) { x.h == h })
      |> option.from_result
      |> option.map(fn(x) {
        Shown(
          h: x.h,
          score: x.score,
          notes: x.notes,
          note_codes: x.note_codes,
          best: False,
        )
      })
  }
}

/// The `hours` entry behind a shown hour, which has the numbers.
pub fn hour_entry(beach: Beach, shown: Option(Shown)) -> Option(Hour) {
  case shown {
    None -> None
    Some(s) ->
      list.find(beach.hours, fn(x) { x.h == s.h }) |> option.from_result
  }
}

fn tide_decoder() -> Decoder(Tide) {
  use time <- decode.field("time", decode.string)
  use m <- decode.field("m", decoders.number())
  use high <- decode.field("high", decode.bool)
  decode.success(Tide(time:, m:, high:))
}

fn sea_decoder() -> Decoder(Sea) {
  let n = decoders.nullable_number()
  use temp_c <- decode.field("temp_c", n)
  use wave_m <- decode.field("wave_m", n)
  use period_s <- decode.field("period_s", n)
  use wave_dir_deg <- decode.field("wave_dir_deg", n)
  use swell_m <- decode.field("swell_m", n)
  use swell_period_s <- decode.field("swell_period_s", n)
  use current_kmh <- decode.field("current_kmh", n)
  use wind_kmh <- decode.field("wind_kmh", n)
  use wind_dir_deg <- decode.field("wind_dir_deg", n)
  use air_temp_c <- decode.field("air_temp_c", n)
  use uv <- decode.field("uv", n)
  use rain_pct <- decode.field("rain_pct", n)
  decode.success(Sea(
    temp_c:,
    wave_m:,
    period_s:,
    wave_dir_deg:,
    swell_m:,
    swell_period_s:,
    current_kmh:,
    wind_kmh:,
    wind_dir_deg:,
    air_temp_c:,
    uv:,
    rain_pct:,
  ))
}

fn whales_decoder() -> Decoder(Whales) {
  use now <- decode.field("now", level.decoder())
  use peak <- decode.field("peak", decode.optional(decode.string))
  use season <- decode.field("season", decode.bool)
  decode.success(Whales(now:, peak:, season:))
}

fn facilities_decoder() -> Decoder(Facilities) {
  let count = fn(key, next) {
    decode.optional_field(key, None, decode.optional(decode.int), next)
  }
  use parking <- count("parking")
  use toilets <- count("toilets")
  use shower <- count("shower")
  use lifeguard <- count("lifeguard")
  decode.success(Facilities(parking:, toilets:, shower:, lifeguard:))
}

pub fn decoder() -> Decoder(Beach) {
  use name <- decode.field("name", decode.string)
  use lat <- decode.field("lat", decoders.number())
  use lon <- decode.field("lon", decoders.number())
  use best <- decode.field("best", hour.best_decoder())
  use hours <- decode.field("hours", decode.list(hour.decoder()))
  use water <- decode.field("water", water.decoder())
  use tides <- decode.field("tides", decode.list(tide_decoder()))
  use sea <- decode.field("sea", sea_decoder())
  use jellyfish <- decode.field("jellyfish", level.decoder())
  use whales <- decode.field("whales", whales_decoder())
  use facilities <- decode.optional_field(
    "facilities",
    None,
    decode.optional(facilities_decoder()),
  )
  decode.success(Beach(
    name:,
    lat:,
    lon:,
    best:,
    hours:,
    water:,
    tides:,
    sea:,
    jellyfish:,
    whales:,
    facilities:,
  ))
}
