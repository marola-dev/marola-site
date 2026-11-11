namespace Marola

/// The wind band an hour carries. A board from before MIP-0054 has none.
[<RequireQualifiedAccess>]
type WindLevel =
    | Calm
    | Breezy
    | Strong
    | Unknown of string

module WindLevel =

    let parse (value: string) : WindLevel =
        match value with
        | "calm" -> WindLevel.Calm
        | "breezy" -> WindLevel.Breezy
        | "strong" -> WindLevel.Strong
        | other -> WindLevel.Unknown other

    let toString (level: WindLevel) : string =
        match level with
        | WindLevel.Calm -> "calm"
        | WindLevel.Breezy -> "breezy"
        | WindLevel.Strong -> "strong"
        | WindLevel.Unknown other -> other

    let decoder = Decoders.enum parse
