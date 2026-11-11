namespace Marola.Client

open Marola

type Camera =
    | Jump of lon: float * lat: float * zoom: float
    | Pan of lon: float * lat: float
    /// west, south, east, north; `maxZoom` keeps a lone beach from filling the screen.
    | Fit of west: float * south: float * east: float * north: float * padding: int * maxZoom: int * instant: bool
    /// The Pacific, whose Nino 3.4 box needs a zoom the area's minimum forbids.
    | Pacific of instant: bool
    | MinZoom of int

/// What `update` asks of the world. A value, not an action: the tests read it, and the App
/// project is the one place that carries it out.
type Cmd =
    | FetchCatalog of Language
    | FetchAreas
    | FetchLatest of area: string
    | FetchBoard of area: string * day: string * file: string
    | FetchTrails of area: string
    | ReplaceUrl of path: string * query: string
    | SetDocument of language: string * title: string
    | StoreLanguage of Language
    | InitMap of lon: float * lat: float
    /// The markers, raster and visibility of the map, as one JSON text.
    | SyncMap of string
    /// The GeoJSON of the trail routes.
    | SetTrails of string
    /// The flow layer's field as JSON, or `null` for none.
    | SetFlow of string
    | MoveCamera of Camera
    | Locate
    | Alert of string
    | Sound of bool
    | Focus of string
