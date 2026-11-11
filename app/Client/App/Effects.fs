/// The one place that carries out what `Update` asks (`Cmd`): requests, and the browser and the
/// map through the two FFI files. Their callbacks come back as messages.
module Marola.Client.App.Effects

open System
open Fable.Core
open Thoth.Json.Core
open Marola
open Marola.Client

// `[body, status]`: status 0 is a body, -1 a network failure, else the HTTP status. One expression in
// JavaScript because the promise chain reads better there than through the binding's overloads.
[<Emit("fetch($0).then(r => r.ok ? r.text().then(b => [b, 0]) : [null, r.status]).catch(() => [null, -1])")>]
let private fetch (url: string) : JS.Promise<string * int> = jsNative

// Every URL starts with "./", so the page works from any path it is served under. A 404 is an
// `HttpError`, which the page words as a missing file.
let private get (url: string) (decoder: Decoder<'a>) (toMsg: Result<'a, FetchError> -> Msg) (dispatch: Msg -> unit) =
    (fetch url)
        .``then`` (fun (body, status) ->
            let result =
                match status with
                | 0 -> Wire.parse decoder body
                | -1 -> Error NetworkError
                | _ -> Error(HttpError status)

            dispatch (toMsg result))
    |> ignore

let run (dispatch: Msg -> unit) (command: Cmd) : unit =
    match command with
    | FetchCatalog language ->
        get
            ("./i18n/" + Language.tag language + ".json")
            I18n.messagesDecoder
            (fun result -> CatalogLoaded(language, result))
            dispatch
    | FetchAreas -> get "./data/areas.json" Area.listDecoder AreasLoaded dispatch
    | FetchLatest area ->
        get ("./data/" + area + "/latest.json") Wire.days (fun result -> LatestLoaded(area, result)) dispatch
    | FetchBoard(area, day, file) ->
        get ("./data/" + area + "/" + file) Wire.board (fun result -> BoardLoaded(area, day, file, result)) dispatch
    | FetchTrails area ->
        get ("./data/trails/" + area + ".json") Trails.decoder (fun result -> TrailsFileLoaded(area, result)) dispatch
    | ReplaceUrl(path, query) -> Ffi.replaceUrl path query
    | SetDocument(language, title) -> Ffi.setDocument language title
    | StoreLanguage language -> Ffi.storeLanguage (Language.tag language)
    | InitMap(lon, lat) ->
        Ffi.initMap
            (MapJson.mapConfig lon lat)
            (Func<string, string, unit>(fun kind arg -> dispatch (MapEvent(kind, arg))))
    | SyncMap json -> Ffi.syncMap json
    | SetTrails geojson -> Ffi.setTrails geojson
    | SetFlow json -> Ffi.setFlow json
    | MoveCamera view -> Ffi.camera (MapJson.cameraJson view)
    | Locate ->
        // `locate` calls back with latitude first.
        Ffi.locate
            (Func<float, float, unit>(fun lat lon -> dispatch (Located(Ok { Lat = lat; Lon = lon }))))
            (Func<string, unit>(fun why -> dispatch (Located(Error why))))
    | Alert text -> Ffi.alertText text
    | Sound on -> Ffi.playSound on Config.soundUrl (Func<unit>(fun () -> dispatch SoundFailed))
    | Focus id -> Ffi.focusId id

/// The commands of one `update`, as Elmish runs them.
let toElmish (commands: Cmd list) : Elmish.Cmd<Msg> =
    commands |> List.map (fun command -> fun dispatch -> run dispatch command)
