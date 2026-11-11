namespace Marola

/// The Low / Moderate / High likelihood of jellyfish and whales.
[<RequireQualifiedAccess>]
type Level =
    | Low
    | Moderate
    | High
    | Unknown of string

module Level =

    let parse (value: string) : Level =
        match value with
        | "Low" -> Level.Low
        | "Moderate" -> Level.Moderate
        | "High" -> Level.High
        | other -> Level.Unknown other

    let toString (level: Level) : string =
        match level with
        | Level.Low -> "Low"
        | Level.Moderate -> "Moderate"
        | Level.High -> "High"
        | Level.Unknown other -> other

    let decoder = Decoders.enum parse
