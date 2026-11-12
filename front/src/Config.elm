module Config exposing (areaCode, areaMinZoom, areaZoom, attributions, bandColour, enabledLayers, gibsAttribution, gibsTiles, instagram, maplibreModule, maplibreWorker, maxZoom, piabrota, playlist, playlistEmbed, pmtilesModule, repo, sourceLink, styleUrl, waveRamp, windRamp)

{-| The constants of the page: where the map comes from, which layers are live, and the colours
MapLibre needs as values. Every colour here is a token of `style.css`.
-}

import Band exposing (Band)


{-| The site's own style (`scripts/basemap_style.mjs` writes it): its glyphs are under `/map/fonts/`
and its tiles are the one PMTiles file the server answers at `/tiles/marola.pmtiles`. No map host
but the page's own.
-}
styleUrl : String
styleUrl =
    "/map/style.json"


{-| The credit the ODbL asks for, the project the tiles and the style come from, and the library that draws them.
-}
attributions : List String
attributions =
    [ "<a href=\"https://www.openstreetmap.org/copyright\" target=\"_blank\" rel=\"noopener\">© OpenStreetMap</a>"
    , "<a href=\"https://protomaps.com\" target=\"_blank\" rel=\"noopener\">Protomaps</a>"
    , "<a href=\"https://maplibre.org\" target=\"_blank\" rel=\"noopener\">MapLibre</a>"
    ]


maplibreModule : String
maplibreModule =
    "/vendor/maplibre/maplibre-gl.mjs"


maplibreWorker : String
maplibreWorker =
    "/vendor/maplibre/maplibre-gl-worker.mjs"


{-| MapLibre reads `pmtiles://` through this library's protocol.
-}
pmtilesModule : String
pmtilesModule =
    "/vendor/pmtiles/pmtiles.mjs"


gibsTiles : String
gibsTiles =
    "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/"


gibsAttribution : String
gibsAttribution =
    "<a href=\"https://www.earthdata.nasa.gov/gibs\">NASA GIBS</a>"


repo : String
repo =
    "https://github.com/marola-dev/marola"


areaZoom : Float
areaZoom =
    10


areaMinZoom : Int
areaMinZoom =
    3


maxZoom : Int
maxZoom =
    17


{-| GREAT RESET, the playlist room.piabrota.art plays (its `assets/config-*.js`, read 2026-11-12).
-}
playlist : String
playlist =
    "https://open.spotify.com/playlist/2hsuqvhCouatM8DtmKKl7U"


{-| Loaded only once the visitor opens the player; the CSP's `frame-src` names this origin alone.
-}
playlistEmbed : String
playlistEmbed =
    "https://open.spotify.com/embed/playlist/2hsuqvhCouatM8DtmKKl7U?theme=0"


piabrota : String
piabrota =
    "https://piabrota.art"


{-| The layers whose button works; the others show as "em breve" and a `?layer=` link to one is
ignored. The wind, wave and satellite layers are built; adding one here turns it on.
-}
enabledLayers : List String
enabledLayers =
    [ "water" ]


bandColour : Band -> String
bandColour band =
    case band of
        Band.Good ->
            "#1b9e77"

        Band.Fair ->
            "#e6ab02"

        Band.Poor ->
            "#d95f02"

        Band.Avoid ->
            "#d7191c"

        Band.Unscored ->
            "#8c8c8c"


{-| `--flow-wind-*` and `--flow-wave-*`, calm to strong.
-}
windRamp : List String
windRamp =
    [ "#5b6db3", "#4a94a9", "#4d9a6e", "#8fa64a", "#b5904a", "#a8566a" ]


waveRamp : List String
waveRamp =
    [ "#2f5a9e", "#4a63b8", "#6b55b3", "#9150a8", "#b4508c", "#c86e6e" ]


{-| The picker's two-letter code; `areas.json` is shared with the app, so the codes live here.
-}
areaCode : String -> String -> String
areaCode id name =
    case id of
        "floripa" ->
            "FL"

        "rio" ->
            "RJ"

        "salvador" ->
            "BA"

        _ ->
            String.filter Char.isAlpha name |> String.left 2 |> String.toUpper


{-| `Just ""` is a city whose account is still coming; an area not listed shows no pill.
-}
instagram : String -> Maybe String
instagram areaId =
    case areaId of
        "floripa" ->
            Just "fl.marola"

        "rio" ->
            Just "rj.marola"

        "salvador" ->
            Just ""

        _ ->
            Nothing


{-| The footer links a source by the first word of its name.
-}
sourceLink : String -> Maybe String
sourceLink source =
    let
        known name =
            case name of
                "OpenStreetMap/Overpass" ->
                    Just "https://www.openstreetmap.org/copyright"

                "Open-Meteo" ->
                    Just "https://open-meteo.com/"

                "IMA/SC" ->
                    Just "https://balneabilidade.ima.sc.gov.br/"

                _ ->
                    Nothing

        first =
            String.split " " source |> List.head |> Maybe.withDefault source
    in
    case known first of
        Just link ->
            Just link

        Nothing ->
            known source
