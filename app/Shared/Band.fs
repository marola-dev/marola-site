namespace Marola

/// The colour band of a score. The page colours by CSS class, never by an inline style: its CSP
/// blocks `style=`.
[<RequireQualifiedAccess>]
type Band =
    | Unscored
    | Avoid
    | Poor
    | Fair
    | Good

module Band =

    /// No score is `Unscored`; an unfit beach or a score of 0 or less is `Avoid`.
    let ofScore (score: int option) (unfit: bool) : Band =
        match score with
        | None -> Band.Unscored
        | Some s when unfit || s <= 0 -> Band.Avoid
        | Some s when s >= 70 -> Band.Good
        | Some s when s >= 40 -> Band.Fair
        | Some _ -> Band.Poor

    let cssClass (band: Band) : string =
        match band with
        | Band.Unscored -> "cna"
        | Band.Avoid -> "c0"
        | Band.Poor -> "c1"
        | Band.Fair -> "c40"
        | Band.Good -> "c70"
