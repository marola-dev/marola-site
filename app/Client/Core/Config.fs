namespace Marola.Client

open Marola

/// The constants of the page: where the map comes from, which layers are live, and the colours
/// that MapLibre needs as values. Every colour here is a token of `style.css`.
module Config =

    /// The base map style, OpenFreeMap's `liberty`. NOBODY TESTED THIS URL: it was not fetched and
    /// no browser loaded it. Its sprite, glyph and tile hosts are assumed to be
    /// `tiles.openfreemap.org`, the only host the CSP (`Csp.fs`) lets the page reach. Change the URL
    /// here and nowhere else.
    let styleUrl = "https://tiles.openfreemap.org/styles/liberty"

    /// The credit the ODbL asks for, and the map's host. The style may carry its own; MapLibre
    /// drops an attribution that another one repeats.
    let attributions =
        [ "<a href=\"https://openfreemap.org\" target=\"_blank\" rel=\"noopener\">OpenFreeMap</a>"
          "<a href=\"https://www.openstreetmap.org/copyright\" target=\"_blank\" rel=\"noopener\">© OpenStreetMap contributors</a>" ]

    let maplibreModule = "/vendor/maplibre/maplibre-gl.mjs"

    let maplibreWorker = "/vendor/maplibre/maplibre-gl-worker.mjs"

    let gibsTiles = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/"

    let gibsAttribution =
        "<a href=\"https://www.earthdata.nasa.gov/gibs\">NASA GIBS</a>"

    let repo = "https://github.com/marola-dev/marola"

    let areaZoom = 10.0

    let areaMinZoom = 3

    let maxZoom = 17

    /// The key of the stored language choice (MIP-0054 5.5).
    let languageKey = "marola.lang"

    /// The wave loop, fetched when the visitor first turns the sound on.
    let soundUrl = "vendor/sounds/waves.mp3"

    /// The layers whose button works. The others show as "em breve", and a `?layer=` link to one is
    /// ignored, as the old page did. The wind, wave and satellite layers are built and tested;
    /// adding one here turns it on.
    let enabledLayers = [ "water" ]

    let bandColour (band: Band) : string =
        match band with
        | Band.Good -> "#1b9e77"
        | Band.Fair -> "#e6ab02"
        | Band.Poor -> "#d95f02"
        | Band.Avoid -> "#d7191c"
        | Band.Unscored -> "#8c8c8c"

    /// The flow layer's colour ramps, calm to strong (`--flow-wind-*`, `--flow-wave-*`).
    let windRamp = [ "#5b6db3"; "#4a94a9"; "#4d9a6e"; "#8fa64a"; "#b5904a"; "#a8566a" ]

    let waveRamp = [ "#2f5a9e"; "#4a63b8"; "#6b55b3"; "#9150a8"; "#b4508c"; "#c86e6e" ]

    let private isLetter (c: char) : bool =
        (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')

    /// The picker shows a two-letter code; `areas.json` is shared with the app, so the codes live here.
    let areaCode (id: string) (name: string) : string =
        match id with
        | "floripa" -> "FL"
        | "rio" -> "RJ"
        | "salvador" -> "BA"
        | _ ->
            name
            |> Seq.filter isLetter
            |> Seq.truncate 2
            |> Seq.map string
            |> String.concat ""
            |> fun s -> s.ToUpperInvariant()

    /// Each city's own Instagram account: `Some ""` is a city whose account is still coming; an
    /// area not listed shows no pill.
    let instagram (areaId: string) : string option =
        match areaId with
        | "floripa" -> Some "fl.marola"
        | "rio" -> Some "rj.marola"
        | "salvador" -> Some ""
        | _ -> None

    /// The footer links a source by the first word of its name.
    let sourceLink (source: string) : string option =
        let known (name: string) =
            match name with
            | "OpenStreetMap/Overpass" -> Some "https://www.openstreetmap.org/copyright"
            | "Open-Meteo" -> Some "https://open-meteo.com/"
            | "IMA/SC" -> Some "https://balneabilidade.ima.sc.gov.br/"
            | _ -> None

        let first = (source.Split ' ').[0]

        match known first with
        | Some link -> Some link
        | None -> known source
