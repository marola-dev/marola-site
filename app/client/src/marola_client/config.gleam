//// The constants of the page: where the map comes from, which layers are
//// live, and the colours that MapLibre needs as values. Every colour here is
//// a token of `style.css`; `scripts/client_check.js` checks that they agree.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import marola/band.{type Band}

/// The base map style, OpenFreeMap's `liberty`. NOBODY TESTED THIS URL: it
/// was not fetched and no browser loaded it. Its sprite, glyph and tile hosts
/// are assumed to be `tiles.openfreemap.org`, which is the only host the CSP
/// (`marola/csp`) lets the page reach. Change the URL here and nowhere else.
pub const style_url = "https://tiles.openfreemap.org/styles/liberty"

/// The credit the ODbL asks for, and the map's host. The style may carry its
/// own; MapLibre drops an attribution that another one repeats.
pub const attributions = [
  "<a href=\"https://openfreemap.org\" target=\"_blank\" rel=\"noopener\">OpenFreeMap</a>",
  "<a href=\"https://www.openstreetmap.org/copyright\" target=\"_blank\" rel=\"noopener\">© OpenStreetMap contributors</a>",
]

pub const maplibre_module = "/vendor/maplibre/maplibre-gl.mjs"

pub const maplibre_worker = "/vendor/maplibre/maplibre-gl-worker.mjs"

pub const gibs_tiles = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/"

pub const gibs_attribution =
  "<a href=\"https://www.earthdata.nasa.gov/gibs\">NASA GIBS</a>"

pub const repo = "https://github.com/marola-dev/marola"

pub const area_zoom = 10.0

pub const area_min_zoom = 3

pub const max_zoom = 17

/// The key of the stored language choice (MIP-0054 5.5).
pub const language_key = "marola.lang"

/// The wave loop, fetched when the visitor first turns the sound on.
pub const sound_url = "vendor/sounds/waves.mp3"

/// The layers whose button works. The others show as "em breve", and a
/// `?layer=` link to one is ignored, as the old page did. The wind, wave and
/// satellite layers are built and tested; adding one here turns it on.
pub const enabled_layers = ["water"]

pub fn band_colour(band: Band) -> String {
  case band {
    band.Good -> "#1b9e77"
    band.Fair -> "#e6ab02"
    band.Poor -> "#d95f02"
    band.Avoid -> "#d7191c"
    band.Unscored -> "#8c8c8c"
  }
}

/// The flow layer's colour ramps, calm to strong (`--flow-wind-*`, `--flow-wave-*`).
pub const wind_ramp = [
  "#5b6db3", "#4a94a9", "#4d9a6e", "#8fa64a", "#b5904a", "#a8566a",
]

pub const wave_ramp = [
  "#2f5a9e", "#4a63b8", "#6b55b3", "#9150a8", "#b4508c", "#c86e6e",
]

/// The picker shows a two-letter code; `areas.json` is shared with the app, so
/// the codes live here.
pub fn area_code(id: String, name: String) -> String {
  case id {
    "floripa" -> "FL"
    "rio" -> "RJ"
    "salvador" -> "BA"
    _ ->
      name
      |> string.to_graphemes
      |> list.filter(fn(c) { string.contains(letters, c) })
      |> list.take(2)
      |> string.join("")
      |> string.uppercase
  }
}

const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

/// Each city's own Instagram account: `Some("")` is a city whose account is
/// still coming; an area not listed shows no pill.
pub fn instagram(area_id: String) -> Option(String) {
  case area_id {
    "floripa" -> Some("fl.marola")
    "rio" -> Some("rj.marola")
    "salvador" -> Some("")
    _ -> None
  }
}

/// The footer links a source by the first word of its name.
pub fn source_link(source: String) -> Option(String) {
  let known = fn(name) {
    case name {
      "OpenStreetMap/Overpass" ->
        Some("https://www.openstreetmap.org/copyright")
      "Open-Meteo" -> Some("https://open-meteo.com/")
      "IMA/SC" -> Some("https://balneabilidade.ima.sc.gov.br/")
      _ -> None
    }
  }
  let first = case string.split(source, " ") {
    [word, ..] -> word
    [] -> source
  }
  option.or(known(first), known(source))
}
