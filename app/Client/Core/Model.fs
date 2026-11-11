namespace Marola.Client

open Marola

/// The map layer on show. `Off` is none; the others are the buttons of the rail.
[<RequireQualifiedAccess>]
type Layer =
    | Off
    | Wind
    | Waves
    | Water
    | Clouds
    | Sst
    | Anomaly
    | Elnino

/// What the map is doing. A failed map keeps the page usable through the list.
type MapState =
    | MapNone
    | MapLoading
    | MapReady
    | MapFailed of noteKey: string

/// The footer's line while the page loads or when it could not.
[<RequireQualifiedAccess>]
type Status =
    | Loading of name: string
    | Failed of error: string * missing: bool
    | NoAreas
    /// A board whose schema this page does not read.
    | TooNew of schema: int
    | Idle

type TrailsFile =
    | TrailsPending
    | TrailsLoaded of Trails
    /// No file for the area: the board's own trails stand in.
    | TrailsMissing

/// The one panel that may fill the map's left edge.
[<RequireQualifiedAccess>]
type Panel =
    | Closed
    | BeachList
    | TrailList

/// One entry of `data/<area>/latest.json`: a day that has a board, and its file.
type DayEntry = { Date: string; File: string }

type Model =
    { Loc: Locale
      CatalogsPending: int
      Path: string
      Query: Query
      Areas: Area list
      Area: Area option
      Days: DayEntry list
      Day: string option
      Board: Board option
      Hours: string list
      Selection: Selection
      Selected: string option
      Here: Point option
      Layer: Layer
      ShowBeaches: bool
      ShowTrails: bool
      Panel: Panel
      TrailSelected: int option
      TrailsFile: TrailsFile
      LoreOpen: bool
      BlurbOpen: bool
      SosOpen: bool
      SoundOn: bool
      Map: MapState
      Status: Status
      ZoomedOut: bool
      Fitted: bool
      ReducedMotion: bool }

module Layer =

    /// The layers of the rail, in order.
    let all =
        [ Layer.Wind
          Layer.Waves
          Layer.Water
          Layer.Clouds
          Layer.Sst
          Layer.Anomaly
          Layer.Elnino ]

    let key (layer: Layer) : string =
        match layer with
        | Layer.Off -> "off"
        | Layer.Wind -> "wind"
        | Layer.Waves -> "waves"
        | Layer.Water -> "water"
        | Layer.Clouds -> "clouds"
        | Layer.Sst -> "sst"
        | Layer.Anomaly -> "anomaly"
        | Layer.Elnino -> "elnino"

    let ofKey (value: string) : Layer option =
        all |> List.tryFind (fun layer -> key layer = value)

    /// A layer whose button works; the rest show as "em breve".
    let enabled (layer: Layer) : bool =
        List.contains (key layer) Config.enabledLayers

module Model =

    /// The trails to draw: the area's file, else the board's own.
    let trails (model: Model) : Trails option =
        match model.TrailsFile, model.Area, model.Board with
        | TrailsLoaded found, _, _ -> Some found
        | TrailsMissing, Some area, Some board -> Some(Trails.fromBoard area.Id board.Trails)
        | _ -> None

    let initial (loc: Locale) (path: string) (query: Query) (reducedMotion: bool) : Model =
        { Loc = loc
          CatalogsPending = 2
          Path = path
          Query = query
          Areas = []
          Area = None
          Days = []
          Day = None
          Board = None
          Hours = []
          Selection = Selection.BestHour
          Selected = None
          Here = None
          Layer = Layer.Off
          ShowBeaches = true
          ShowTrails = true
          Panel = Panel.Closed
          TrailSelected = None
          TrailsFile = TrailsPending
          LoreOpen = false
          BlurbOpen = false
          SosOpen = false
          SoundOn = false
          Map = MapNone
          Status = Status.Idle
          ZoomedOut = false
          Fitted = false
          ReducedMotion = reducedMotion }

    /// The beaches of the board on show, or none.
    let beaches (model: Model) : Beach list =
        match model.Board with
        | Some board -> board.Beaches
        | None -> []
