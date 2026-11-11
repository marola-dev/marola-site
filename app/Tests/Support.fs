/// Shared helpers of the tests: the files they read and the JSON reader of each runtime.
module Marola.Tests.Support

open Thoth.Json.Core
open Marola

#if FABLE_COMPILER
open Fable.Core

[<ImportMember("node:fs")>]
let private readFileSync (path: string, encoding: string) : string = jsNative

[<ImportMember("node:fs")>]
let private existsSync (path: string) : bool = jsNative

[<Emit("process.cwd()")>]
let private cwd () : string = jsNative

let private exists (path: string) = existsSync path
let private readAll (path: string) = readFileSync (path, "utf8")
let private startDir = cwd ()
#else
let private exists (path: string) = System.IO.File.Exists path
let private readAll (path: string) = System.IO.File.ReadAllText path
let private startDir = System.AppContext.BaseDirectory.TrimEnd '/'
#endif

/// The repository root: the nearest folder above the start that holds the board schema. The
/// tests run from `app`, from a project folder or from the build output, so none is assumed.
let rec private findRoot (dir: string) : string =
    if exists (dir + "/site/board.schema.json") then
        dir
    else
        match dir.LastIndexOf '/' with
        | i when i > 0 -> findRoot (dir.Substring(0, i))
        | _ -> failwith "repository root not found: no site/board.schema.json above the start"

let root = findRoot startDir

/// A file of the repository, by its path from the root.
let read (path: string) : string = readAll (root + "/" + path)

let parse (decoder: Decoder<'a>) (text: string) : Result<'a, string> =
#if FABLE_COMPILER
    Thoth.Json.JavaScript.Decode.fromString decoder text
#else
    Thoth.Json.Newtonsoft.Decode.fromString decoder text
#endif

/// The value, or a failed test with the decoder's message.
let parseOrFail (decoder: Decoder<'a>) (text: string) : 'a =
    match parse decoder text with
    | Ok value -> value
    | Error message -> failwith ("bad JSON: " + message)

/// The real catalogs of the site, read once.
let private catalogCache =
    lazy
        (let messages tag =
            parseOrFail I18n.messagesDecoder (read ("site/i18n/" + tag + ".json"))

         Map.ofList [ Language.PtBr, messages "pt-BR"; Language.En, messages "en" ])

let catalog () : Catalog = catalogCache.Value

let locale (language: Language) : Locale =
    { Catalog = catalog ()
      Language = language }

/// A one-language catalog from key and message pairs.
let catalogOf (messages: (string * string) list) : Catalog =
    Map.ofList [ Language.En, Map.ofList messages ]

let private goldenText = lazy (read "app/Tests/golden.json")

/// One section of `golden.json`, each entry through `entry`.
let golden (section: string) (entry: Decoder<'a>) : 'a list =
    parseOrFail (Decode.field section (Decode.list entry)) goldenText.Value

let goldenOne (section: string) (decoder: Decoder<'a>) : 'a =
    parseOrFail (Decode.field section decoder) goldenText.Value

let langDecoder: Decoder<Language> =
    Decode.string
    |> Decode.andThen (fun tag ->
        match Language.fromTag tag with
        | Some language -> Decode.succeed language
        | None -> Decode.fail ("unknown language " + tag))

let private variantsCache = lazy (goldenOne "variants" (Decode.dict Beach.decoder))

/// The beach the golden cases name.
let beachNamed (name: string) : Beach =
    match Map.tryFind name variantsCache.Value with
    | Some b -> b
    | None -> failwith ("no golden beach " + name)

/// Message arguments as the golden file writes them: numbers and text.
let argsDecoder: Decoder<(string * IcuArg) list> =
    let arg =
        Decode.oneOf [ Decoders.number |> Decode.map Num; Decode.string |> Decode.map Text ]

    Decode.dict arg |> Decode.map Map.toList

/// The slider position the golden cases write: no hour is the best hour.
let selection (hour: string option) : Selection =
    match hour with
    | None -> Selection.BestHour
    | Some h -> Selection.At h

/// Relative tolerance, with the scale of the expected number held at 1 or more.
let close (a: float) (b: float) (tolerance: float) : bool =
    let scale = if abs a > 1.0 then abs a else 1.0
    abs (a - b) <= tolerance * scale

let allClose (a: float list) (b: float list) (tolerance: float) : bool =
    List.length a = List.length b
    && List.forall2 (fun x y -> close x y tolerance) a b
