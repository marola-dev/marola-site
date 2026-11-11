namespace Marola

/// A trail's OSM `sac_scale`. Only two values are known; the rest keep their wire text so a new
/// OSM value shows up as unrated, not as a crash.
[<RequireQualifiedAccess>]
type Difficulty =
    | Hiking
    | MountainHiking
    | Unrated
    | Unknown of string

module Difficulty =

    let parse (value: string option) : Difficulty =
        match value with
        | Some "hiking" -> Difficulty.Hiking
        | Some "mountain_hiking" -> Difficulty.MountainHiking
        | Some other -> Difficulty.Unknown other
        | None -> Difficulty.Unrated

    let toString (difficulty: Difficulty) : string option =
        match difficulty with
        | Difficulty.Hiking -> Some "hiking"
        | Difficulty.MountainHiking -> Some "mountain_hiking"
        | Difficulty.Unknown other -> Some other
        | Difficulty.Unrated -> None

    /// The colour band of a trail line: the same classes the score chips use.
    let band (difficulty: Difficulty) : Band =
        match difficulty with
        | Difficulty.Hiking -> Band.Good
        | Difficulty.MountainHiking -> Band.Fair
        | _ -> Band.Unscored

    let decoder = Decoders.nullableString |> Thoth.Json.Core.Decode.map parse
