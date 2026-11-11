namespace Marola.Client

open Marola

/// What the page reads from the browser before it starts.
type Env =
    { Path: string
      Query: Query
      Languages: string list
      StoredLanguage: string option
      ReducedMotion: bool }

/// The page's one state machine: a message and a model in, a model and a list of commands out.
/// Nothing here touches the browser, so every path is a test.
module Update =

    // ---- what every part shares: the query string, the commands that bring the map up to date,
    // and the way a failed request reads in the footer.

    let private active (model: Model) : bool =
        model.Map = MapLoading || model.Map = MapReady

    let private setParam (model: Model) (key: string) (value: string) : Model =
        { model with
            Query = Params.set model.Query key value }

    let private deleteParam (model: Model) (key: string) : Model =
        { model with
            Query = Params.delete model.Query key }

    let private url (model: Model) : Cmd =
        ReplaceUrl(model.Path, Params.toString model.Query)

    /// The markers, raster and visibility, when there is a map to hold them.
    let private sync (model: Model) (more: Cmd list) : Model * Cmd list =
        if active model then
            model, SyncMap(MapView.syncJson model) :: more
        else
            model, more

    let private trailCmds (model: Model) : Cmd list =
        if active model then
            [ SetTrails(TrailGeo.collection (Model.trails model) model.Loc) ]
        else
            []

    let private flowCmds (model: Model) : Cmd list =
        if active model then
            [ SetFlow(FlowData.json model) ]
        else
            []

    let private currentArea (model: Model) : string option =
        model.Area |> Option.map (fun a -> a.Id)

    /// The answer to a request for an area the visitor has left is not theirs any more.
    let private guardArea (model: Model) (area: string) (next: unit -> Model * Cmd list) : Model * Cmd list =
        if currentArea model = Some area then next () else model, []

    let private guardDay
        (model: Model)
        (area: string)
        (day: string)
        (next: unit -> Model * Cmd list)
        : Model * Cmd list =
        if currentArea model = Some area && model.Day = Some day then
            next ()
        else
            model, []

    /// What the footer says of a failed request: the status and the path, as the old page's
    /// `fetchJson` did. The flag is true for a missing file.
    let describe (error: FetchError) (path: string) : string * bool =
        match error with
        | HttpError status -> string status + " " + path, status = 404
        | NetworkError -> "network error " + path, false
        | BadUrl -> "bad address " + path, false
        | BadData _ -> "bad data " + path, false

    let private fail (model: Model) (error: FetchError) (path: string) : Model * Cmd list =
        let text, missing = describe error path

        { model with
            Status = Status.Failed(text, missing) },
        []

    // ---- data arriving: catalogs, areas, days, boards and trails, and the choice of an area or a
    // day that starts a load.

    let private catalogLoaded
        (model: Model)
        (language: Language)
        (result: Result<Map<string, string>, FetchError>)
        : Model * Cmd list =
        let catalog =
            match result with
            | Ok messages -> Map.add language messages model.Loc.Catalog
            | Error _ -> model.Loc.Catalog

        let pending = model.CatalogsPending - 1

        let next =
            { model with
                Loc = { model.Loc with Catalog = catalog }
                CatalogsPending = pending }

        let next =
            match result with
            | Error e ->
                { next with
                    Status = Status.Failed(fst (describe e ("i18n/" + Language.tag language + ".json")), false) }
            | Ok _ -> next

        if pending = 0 then
            next,
            [ SetDocument(Language.tag model.Loc.Language, I18n.t next.Loc "title.map" [])
              FetchAreas ]
        else
            next, []

    let private selectArea (model: Model) (area: Area) : Model * Cmd list =
        let firstMap = model.Map = MapNone

        let next =
            { model with
                Area = Some area
                Status = Status.Loading area.Name
                TrailsFile = TrailsPending
                TrailSelected = None
                Map = (if firstMap then MapLoading else model.Map) }

        let next = setParam next "area" area.Id

        let mapCmd =
            if firstMap then
                InitMap(area.Lon, area.Lat)
            else
                MoveCamera(Jump(area.Lon, area.Lat, Config.areaZoom))

        next, [ url next; mapCmd; FetchLatest area.Id; FetchTrails area.Id ]

    let private areasLoaded (model: Model) (areas: Area list) : Model * Cmd list =
        let wanted = Params.get model.Query "area"

        let chosen =
            match areas |> List.tryFind (fun a -> Some a.Id = wanted) with
            | Some area -> Some area
            | None -> List.tryHead areas

        match chosen with
        | None ->
            { model with
                Areas = areas
                Status = Status.NoAreas },
            []
        | Some area -> selectArea { model with Areas = areas } area

    let private areaPicked (model: Model) (id: string) : Model * Cmd list =
        match model.Areas |> List.tryFind (fun a -> a.Id = id) with
        | None -> model, []
        | Some area ->
            // A new area starts afresh: no beach picked, the map fits its beaches.
            let reset =
                { model with
                    Fitted = false
                    Selected = None
                    Board = None
                    Day = None }
                |> fun m -> deleteParam m "beach"
                |> fun m -> deleteParam m "day"

            let next, cmds = selectArea reset area
            next, cmds @ snd (sync next [])

    let private selectDay (model: Model) (day: DayEntry) : Model * Cmd list =
        let next =
            { model with
                Day = Some day.Date
                Status = Status.Loading day.Date }

        let next = setParam next "day" day.Date
        let area = currentArea model |> Option.defaultValue ""
        next, [ url next; FetchBoard(area, day.Date, day.File) ]

    let private latestLoaded (model: Model) (area: string) (days: DayEntry list) : Model * Cmd list =
        guardArea model area (fun () ->
            let wanted = Params.get model.Query "day"
            let byParam = days |> List.tryFind (fun d -> Some d.Date = wanted)

            match byParam |> Option.orElse (List.tryLast days) with
            | None ->
                { model with
                    Days = days
                    Status = Status.Failed("no days " + area, false) },
                []
            | Some day -> selectDay { model with Days = days } day)

    let private dayPicked (model: Model) (day: string) : Model * Cmd list =
        match model.Days |> List.tryFind (fun d -> d.Date = day) with
        | Some found -> selectDay model found
        | None -> model, []

    /// The first board of an area fits the map to its beaches; a picked layer that zoomed the map
    /// out keeps its view.
    let private fit (model: Model) : bool * Cmd list =
        match model.Board with
        | Some board when not (model.Fitted || model.ZoomedOut || not (active model)) ->
            match MapView.beachBounds board with
            | Some(w, s, e, n) -> true, [ MoveCamera(Fit(w, s, e, n, 40, 13, true)) ]
            | None -> false, []
        | _ -> model.Fitted, []

    let private showBoard (model: Model) (board: Board) : Model * Cmd list =
        let fromUrl =
            match Params.get model.Query "beach", model.Selected with
            | Some name, None ->
                if board.Beaches |> List.exists (fun b -> b.Name = name) then
                    Some name
                else
                    None
            | _, selected -> selected

        let next =
            { model with
                Board = Some board
                Hours = Board.hours board
                Selection = Selection.BestHour
                Selected = fromUrl
                Status = Status.Idle }

        let fitted, fitCmds = fit next
        let next = { next with Fitted = fitted }
        sync next (fitCmds @ trailCmds next @ flowCmds next)

    let private boardLoaded
        (model: Model)
        (area: string)
        (file: string)
        (result: Result<Loaded, FetchError>)
        : Model * Cmd list =
        match result with
        | Error e -> fail model e ("data/" + area + "/" + file)
        | Ok(Newer schema) ->
            { model with
                Status = Status.TooNew schema },
            []
        | Ok(Read board) -> showBoard model board

    let private trailsLoaded (model: Model) (result: Result<Trails, FetchError>) : Model * Cmd list =
        let next =
            match result with
            | Ok found ->
                { model with
                    TrailsFile = TrailsLoaded found }
            | Error _ ->
                { model with
                    TrailsFile = TrailsMissing }

        next, trailCmds next

    // ---- the visitor: the slider, the picked beach, the layers, the panels, the language and the
    // map's own events.

    let private hourMoved (model: Model) (index: int) : Model * Cmd list =
        let selection =
            match (if index >= 0 then List.tryItem index model.Hours else None) with
            | Some h -> Selection.At h
            | None -> Selection.BestHour

        let next = { model with Selection = selection }
        sync next (flowCmds next)

    let private findBeach (model: Model) (name: string) : Beach option =
        Model.beaches model |> List.tryFind (fun b -> b.Name = name)

    let private beachPicked (model: Model) (name: string) (pan: bool) : Model * Cmd list =
        let next =
            { model with
                Selected = Some name
                TrailSelected = None }

        let next = setParam next "beach" name

        let camera =
            match pan, active next, findBeach next name with
            | true, true, Some b -> [ MoveCamera(Pan(b.Lon, b.Lat)) ]
            | _ -> []

        sync next (url next :: camera)

    /// The card of a beach or of a trail closes; a click on the empty map does the same.
    let private closeCards (model: Model) : Model * Cmd list =
        match model.Selected, model.TrailSelected with
        | None, None -> model, []
        | _ ->
            let next =
                deleteParam
                    { model with
                        Selected = None
                        TrailSelected = None }
                    "beach"

            sync next [ url next ]

    /// El Nino needs the Pacific in view, below the area's own minimum zoom.
    let private zoomForLayer (model: Model) : Model * Cmd list =
        let nino = model.Layer = Layer.Elnino

        if nino = model.ZoomedOut then
            model, []
        else
            let next = { model with ZoomedOut = nino }

            let minZoom = MoveCamera(MinZoom(if nino then 0 else Config.areaMinZoom))

            let bounds = next.Board |> Option.bind MapView.beachBounds

            let view =
                match nino, bounds with
                | true, _ -> [ MoveCamera(Pacific next.ReducedMotion) ]
                | false, Some(w, s, e, n) -> [ MoveCamera(Fit(w, s, e, n, 40, 13, next.ReducedMotion)) ]
                | false, None -> []

            next, minZoom :: view

    let private layerPressed (model: Model) (layer: Layer) : Model * Cmd list =
        if not (Layer.enabled layer) then
            model, []
        else
            // A pressed layer button turns its layer off again.
            let picked = if layer = model.Layer then Layer.Off else layer
            let next = setParam { model with Layer = picked } "layer" (Layer.key picked)
            let next, camera = zoomForLayer next
            sync next (camera @ flowCmds next @ [ url next ])

    let private toggled (model: Model) (key: string) (on: bool) : Model * Cmd list =
        let flag = if on then "1" else "0"

        let next =
            match key with
            | "beaches" -> { model with ShowBeaches = on }
            | _ -> { model with ShowTrails = on }

        let next = setParam next key flag
        sync next [ url next ]

    let private panelToggled (model: Model) (panel: Panel) : Model * Cmd list =
        { model with
            Panel = (if model.Panel = panel then Panel.Closed else panel) },
        []

    let private routeBounds (route: Route) : (float * float * float * float) option =
        match Trails.drawableLines route |> List.concat with
        | [] -> None
        | first :: rest ->
            rest
            |> List.fold
                (fun (w, s, e, n) (p: Point) -> min w p.Lon, min s p.Lat, max e p.Lon, max n p.Lat)
                (first.Lon, first.Lat, first.Lon, first.Lat)
            |> Some

    let private trailChosen (model: Model) (id: int) (fit: bool) : Model * Cmd list =
        match Model.trails model |> Option.bind (fun t -> Trails.routeAt t id) with
        | Some route ->
            let next =
                deleteParam
                    { model with
                        TrailSelected = Some id
                        Selected = None }
                    "beach"

            let camera =
                match fit, active next, routeBounds route with
                | true, true, Some(w, s, e, n) -> [ MoveCamera(Fit(w, s, e, n, 60, 15, next.ReducedMotion)) ]
                | _ -> []

            sync next (url next :: camera)
        | None -> model, []

    let private nearPressed (model: Model) : Model * Cmd list =
        match model.Here with
        | Some _ -> sync { model with Here = None } []
        | None -> model, [ Locate ]

    let private foldToggled (model: Model) (fold: Fold) : Model =
        match fold with
        | LoreFold ->
            { model with
                LoreOpen = not model.LoreOpen }
        | BlurbFold ->
            { model with
                BlurbOpen = not model.BlurbOpen }

    let private sosClosed (model: Model) : Model * Cmd list =
        if model.SosOpen then
            { model with SosOpen = false }, [ Focus "sos" ]
        else
            model, []

    let private languagePicked (model: Model) (language: Language) : Model * Cmd list =
        if language = model.Loc.Language then
            model, []
        else
            let next =
                setParam
                    { model with
                        Loc = { model.Loc with Language = language } }
                    "lang"
                    (Language.tag language)

            let next, cmds = sync next (trailCmds next)

            next,
            [ StoreLanguage language
              url next
              SetDocument(Language.tag language, I18n.t next.Loc "title.map" []) ]
            @ cmds

    let private mapEvent (model: Model) (kind: string) (arg: string) : Model * Cmd list =
        match kind, Parse.tryInt arg with
        | "ready", _ -> { model with Map = MapReady }, []
        | "error", _ ->
            // An error before the map loads is the style or its sprites: the list carries the page,
            // and says why there is no map.
            match model.Map with
            | MapLoading ->
                { model with
                    Map = MapFailed "map.failed"
                    Panel = Panel.BeachList },
                []
            | _ -> model, []
        | "click", _ -> closeCards model
        | "beach", _ -> beachPicked model arg false
        | "trail", Some id -> trailChosen model id false
        | _ -> model, []

    // ---- the entry points

    let init (env: Env) : Model * Cmd list =
        let language =
            Language.resolve (Params.get env.Query "lang") env.StoredLanguage env.Languages Language.all

        let loc =
            { Catalog = Map.empty
              Language = language }

        let baseModel = Model.initial loc env.Path env.Query env.ReducedMotion

        let layer =
            Params.get env.Query "layer"
            |> Option.bind Layer.ofKey
            |> Option.filter Layer.enabled
            |> Option.defaultValue Layer.Off

        let start =
            { baseModel with
                Layer = layer
                ShowBeaches = Params.get env.Query "beaches" <> Some "0"
                ShowTrails = Params.get env.Query "trails" <> Some "0"
                ZoomedOut = (layer = Layer.Elnino) }

        start, Language.all |> List.map FetchCatalog

    let update (model: Model) (message: Msg) : Model * Cmd list =
        match message with
        | CatalogLoaded(language, result) -> catalogLoaded model language result
        | AreasLoaded(Ok areas) -> areasLoaded model areas
        | AreasLoaded(Error e) -> fail model e "data/areas.json"
        | LatestLoaded(area, Ok days) -> latestLoaded model area days
        | LatestLoaded(area, Error e) -> guardArea model area (fun () -> fail model e ("data/" + area + "/latest.json"))
        | BoardLoaded(area, day, file, result) -> guardDay model area day (fun () -> boardLoaded model area file result)
        | TrailsFileLoaded(area, result) -> guardArea model area (fun () -> trailsLoaded model result)
        | AreaPicked id -> areaPicked model id
        | DayPicked day -> dayPicked model day
        | HourMoved index -> hourMoved model index
        | BeachPicked(name, pan) -> beachPicked model name pan
        | CardClosed -> closeCards model
        | LayerPressed layer -> layerPressed model layer
        | BeachesToggled -> toggled model "beaches" (not model.ShowBeaches)
        | TrailsToggled -> toggled model "trails" (not model.ShowTrails)
        | ListToggled -> panelToggled model Panel.BeachList
        | TrailPanelToggled -> panelToggled model Panel.TrailList
        | TrailChosen(id, fit) -> trailChosen model id fit
        | NearPressed -> nearPressed model
        | Located(Ok point) ->
            sync
                { model with
                    Here = Some point
                    Panel = Panel.BeachList }
                []
        | Located(Error _) -> model, [ Alert(I18n.t model.Loc "near.denied" []) ]
        | FoldToggled fold -> foldToggled model fold, []
        | SosToggled ->
            { model with
                SosOpen = not model.SosOpen },
            []
        | SosClosed -> sosClosed model
        | LanguagePicked language -> languagePicked model language
        | SoundPressed ->
            { model with
                SoundOn = not model.SoundOn },
            [ Sound(not model.SoundOn) ]
        | SoundFailed -> { model with SoundOn = false }, []
        | MapEvent(kind, arg) -> mapEvent model kind arg
