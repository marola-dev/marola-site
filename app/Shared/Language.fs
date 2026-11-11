namespace Marola

/// The two languages of the page (MIP-0054 5.5).
[<RequireQualifiedAccess>]
type Language =
    | PtBr
    | En

module Language =

    /// The language of the source text: a message missing elsewhere falls back to it.
    let source = Language.PtBr

    let all = [ Language.PtBr; Language.En ]

    let tag (language: Language) : string =
        match language with
        | Language.PtBr -> "pt-BR"
        | Language.En -> "en"

    /// A catalog key, exactly as the catalogs write it.
    let fromTag (value: string) : Language option =
        all |> List.tryFind (fun language -> tag language = value)

    let private primarySubtag (tag: string) : string = (tag.Split '-').[0]

    /// A language tag against the supported ones: the exact tag first (ignoring case), then the
    /// first with the same primary subtag ("pt" finds pt-BR).
    let matching (value: string option) (supported: Language list) : Language option =
        match value with
        | None
        | Some "" -> None
        | Some raw ->
            let lower = raw.ToLowerInvariant()

            let by (wanted: string) (primary: bool) =
                supported
                |> List.tryFind (fun language ->
                    let candidate = (tag language).ToLowerInvariant()

                    if primary then
                        primarySubtag candidate = wanted
                    else
                        candidate = wanted)

            match by lower false with
            | Some language -> Some language
            | None -> by (primarySubtag lower) true

    /// ?lang=, then the stored choice, then the browser's languages, then pt-BR.
    let resolve
        (param: string option)
        (stored: string option)
        (languages: string list)
        (supported: Language list)
        : Language =
        param :: stored :: List.map Some languages
        |> List.tryPick (fun t -> matching t supported)
        |> Option.defaultValue source
