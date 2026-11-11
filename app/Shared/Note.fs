namespace Marola

open Thoth.Json.Core

/// The reason codes of a score (MIP-0054 section 5.1). The page words each code per language; a
/// code it does not know keeps the board's English.
[<RequireQualifiedAccess>]
type NoteCode =
    | RoughSeas
    | Choppy
    | NoWaveData
    | StrongWind
    | Breezy
    | NoWindData
    | ColdWater
    | WarmWater
    | NoSeaTempData
    | RainLikely
    | Dark
    | JellyfishElevated
    | JellyfishSome
    | WaterStale
    | WaterUnfit
    | WaterMixed
    | Unknown of string

/// The args of a code: numbers stay numbers, `avoid` is a list of places.
[<RequireQualifiedAccess>]
type NoteArg =
    | Number of float
    | Text of string
    | Places of string list
    | Other

type Note =
    { Code: NoteCode
      Args: Map<string, NoteArg> }

module NoteCode =

    let parse (value: string) : NoteCode =
        match value with
        | "rough_seas" -> NoteCode.RoughSeas
        | "choppy" -> NoteCode.Choppy
        | "no_wave_data" -> NoteCode.NoWaveData
        | "strong_wind" -> NoteCode.StrongWind
        | "breezy" -> NoteCode.Breezy
        | "no_wind_data" -> NoteCode.NoWindData
        | "cold_water" -> NoteCode.ColdWater
        | "warm_water" -> NoteCode.WarmWater
        | "no_sea_temp_data" -> NoteCode.NoSeaTempData
        | "rain_likely" -> NoteCode.RainLikely
        | "dark" -> NoteCode.Dark
        | "jellyfish_elevated" -> NoteCode.JellyfishElevated
        | "jellyfish_some" -> NoteCode.JellyfishSome
        | "water_stale" -> NoteCode.WaterStale
        | "water_unfit" -> NoteCode.WaterUnfit
        | "water_mixed" -> NoteCode.WaterMixed
        | other -> NoteCode.Unknown other

    let toString (code: NoteCode) : string =
        match code with
        | NoteCode.RoughSeas -> "rough_seas"
        | NoteCode.Choppy -> "choppy"
        | NoteCode.NoWaveData -> "no_wave_data"
        | NoteCode.StrongWind -> "strong_wind"
        | NoteCode.Breezy -> "breezy"
        | NoteCode.NoWindData -> "no_wind_data"
        | NoteCode.ColdWater -> "cold_water"
        | NoteCode.WarmWater -> "warm_water"
        | NoteCode.NoSeaTempData -> "no_sea_temp_data"
        | NoteCode.RainLikely -> "rain_likely"
        | NoteCode.Dark -> "dark"
        | NoteCode.JellyfishElevated -> "jellyfish_elevated"
        | NoteCode.JellyfishSome -> "jellyfish_some"
        | NoteCode.WaterStale -> "water_stale"
        | NoteCode.WaterUnfit -> "water_unfit"
        | NoteCode.WaterMixed -> "water_mixed"
        | NoteCode.Unknown other -> other

module Note =

    /// A value of any other shape (null, an object) is `Other`, never an error.
    let private argDecoder: Decoder<NoteArg> =
        Decode.oneOf
            [ Decoders.number |> Decode.map NoteArg.Number
              Decode.string |> Decode.map NoteArg.Text
              Decode.list Decode.string |> Decode.map NoteArg.Places
              Decode.succeed NoteArg.Other ]

    let decoder: Decoder<Note> =
        Decode.object (fun get ->
            { Code = get.Required.Field "code" (Decoders.enum NoteCode.parse)
              Args = get.Required.Field "args" (Decode.dict argDecoder) })
