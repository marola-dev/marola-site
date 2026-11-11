namespace Marola.Client

open Marola

/// Why a request gave no data, as the footer words it (`Update.describe`).
type FetchError =
    | HttpError of status: int
    | NetworkError
    | BadUrl
    /// The body arrived and did not decode.
    | BadData of string

/// A board file, or the news that it is newer than this page.
type Loaded =
    | Read of Board
    /// The schema number the file carries; this page reads `Board.schemas`.
    | Newer of schema: int

type Fold =
    | LoreFold
    | BlurbFold

/// What can happen on the page.
type Msg =
    // Data arrived, or did not.
    | CatalogLoaded of Language * Result<Map<string, string>, FetchError>
    | AreasLoaded of Result<Area list, FetchError>
    | LatestLoaded of area: string * Result<DayEntry list, FetchError>
    | BoardLoaded of area: string * day: string * file: string * Result<Loaded, FetchError>
    | TrailsFileLoaded of area: string * Result<Trails, FetchError>
    // The visitor.
    | AreaPicked of string
    | DayPicked of string
    /// The slider's position: -1 is each beach at its own best hour.
    | HourMoved of int
    /// `pan` is true from the list and false from the map, where it is already in view.
    | BeachPicked of name: string * pan: bool
    | CardClosed
    | LayerPressed of Layer
    | BeachesToggled
    | TrailsToggled
    | ListToggled
    | TrailPanelToggled
    /// `fit` is true from the panel, which names a route the map may not show.
    | TrailChosen of id: int * fit: bool
    | NearPressed
    | Located of Result<Point, string>
    | FoldToggled of Fold
    | SosToggled
    | SosClosed
    | LanguagePicked of Language
    | SoundPressed
    | SoundFailed
    /// An event of the map, named by `maplibre_ffi.mjs`: `ready`, `error`, `click`, `beach` and
    /// `trail`; `arg` is the beach name or the route id.
    | MapEvent of kind: string * arg: string
