/// The exports of the two `.mjs` files in `app/Client/ffi`, one binding each. MapLibre, WebGL and
/// the browser's storage, history and audio live behind them; their arguments are strings, numbers
/// and callbacks, so no F# value crosses except a `Func`, which Fable compiles to a plain lambda.
/// The files are not edited from here: a change of a signature starts in the file.
module Marola.Client.App.Ffi

open System
open Fable.Core

[<Literal>]
let private maplibre = "../ffi/maplibre_ffi.mjs"

[<Literal>]
let private flow = "../ffi/flow_layer_ffi.mjs"

/// `emit kind arg` reports the map's events: `ready`, `error`, `click`, `beach`, `trail`.
[<Import("initMap", maplibre)>]
let initMap (configJson: string) (emit: Func<string, string, unit>) : unit = jsNative

[<Import("syncMap", maplibre)>]
let syncMap (json: string) : unit = jsNative

[<Import("setTrails", maplibre)>]
let setTrails (geojson: string) : unit = jsNative

[<Import("setFlow", maplibre)>]
let setFlow (json: string) : unit = jsNative

[<Import("camera", maplibre)>]
let camera (json: string) : unit = jsNative

/// `onOk latitude longitude`, or `onErr reason`.
[<Import("locate", maplibre)>]
let locate (onOk: Func<float, float, unit>) (onErr: Func<string, unit>) : unit = jsNative

/// Plays or pauses the loop at `url`; `onFail` runs when the browser refuses to play.
[<Import("playSound", maplibre)>]
let playSound (on: bool) (url: string) (onFail: Func<unit>) : unit = jsNative

/// Never throws: a browser with storage off keeps the choice for the visit only.
[<Import("storeLanguage", maplibre)>]
let storeLanguage (tag: string) : unit = jsNative

/// The stored language tag, or "" when there is none or the storage throws.
[<Import("readLanguage", maplibre)>]
let readLanguage () : string = jsNative

[<Import("replaceUrl", maplibre)>]
let replaceUrl (path: string) (query: string) : unit = jsNative

[<Import("alertText", maplibre)>]
let alertText (text: string) : unit = jsNative

[<Import("setDocument", maplibre)>]
let setDocument (language: string) (title: string) : unit = jsNative

[<Import("focusId", maplibre)>]
let focusId (id: string) : unit = jsNative

/// `{path, search, languages, reduced_motion}` as JSON text.
[<Import("readEnv", maplibre)>]
let readEnv () : string = jsNative

/// A MapLibre custom layer; `maplibre_ffi.mjs` is its only caller, through `setFlow`.
[<Import("createFlowLayer", flow)>]
let createFlowLayer (id: string) : obj = jsNative
