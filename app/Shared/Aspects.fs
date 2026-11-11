namespace Marola

type Facility = { Key: string; Text: string }

/// One cell of a tooltip or card.
type AspectCell =
    /// `Dir` is the compass word, kept apart so the page can mark it up: it is the one part of the
    /// cell that keeps its capitals.
    | Wind of text: string * dir: string option
    | WaterTemp of string
    | Waves of string
    | Jellyfish of string
    | Whales of string
    | Quality of text: string * unfit: bool * dotClass: string
    | FacilityCounts of Facility list

/// `Cells` is empty when the beach is dark at that hour.
type Aspects =
    { Head: string; Cells: AspectCell list }

/// The aspect cells of a beach tooltip and card: wind, water, waves, jellyfish, whales, water
/// quality and facilities. It is app.js `aspectsHtml` as data: the renderer adds icons and
/// escapes the text.
module Aspects =

    /// The cell's reading as one line of text.
    let cellText (cell: AspectCell) : string =
        match cell with
        | Wind(text, None) -> text
        | Wind(text, Some dir) -> text + " " + dir
        | WaterTemp text
        | Waves text
        | Jellyfish text
        | Whales text -> text
        | Quality(text, _, _) -> text
        | FacilityCounts parts -> parts |> List.map (fun p -> p.Text) |> String.concat " · "

    let yesNo (flag: bool) : string = if flag then "yes" else "no"

    let private headText (shown: Shown option) (loc: Locale) : string =
        match shown with
        | Some s -> I18n.t loc "tip.at" [ I18n.numberArg "score" (float s.Score); I18n.arg "h" s.H ]
        | None -> I18n.t loc "tip.dark" []

    let private levelWord (loc: Locale) (level: Level) : string =
        I18n.word loc "lvl." (Level.toString level)

    let private windCell (beach: Beach) (e: Hour) (s: Shown) (loc: Locale) : AspectCell =
        let kmh = Fmt.value loc e.WindKmh " km/h" 0

        // An older board has no band: the number only, no word.
        let bandWord =
            match e.WindLevel |> Option.map WindLevel.toString with
            | Some ""
            | None -> None
            | Some raw -> Some(I18n.word loc "wind." raw)

        let reading =
            match bandWord with
            | Some word -> word + ", " + kmh
            | None -> I18n.t loc "cell.wind" [ I18n.arg "v" kmh ]

        match s.Best, beach.Sea.WindDirDeg with
        | true, Some deg -> Wind(reading, Some(I18n.word loc "dir." (Geo.compassKey deg)))
        | _ -> Wind(reading, None)

    let private whalesText (beach: Beach) (e: Hour) (loc: Locale) : string =
        let peak =
            match beach.Whales.Peak with
            | Some p -> p <> "" && p <> e.H
            | None -> false

        I18n.t
            loc
            "cell.whales"
            [ I18n.arg "level" (levelWord loc e.Whales)
              I18n.arg "best" (yesNo peak)
              I18n.arg "peak" (beach.Whales.Peak |> Option.defaultValue "") ]

    let private facilityParts (facilities: Facilities option) (loc: Locale) : Facility list =
        match facilities with
        | None -> []
        | Some f ->
            [ "parking", f.Parking
              "toilets", f.Toilets
              "shower", f.Shower
              "lifeguard", f.Lifeguard ]
            |> List.choose (fun (key, count) ->
                count
                |> Option.map (fun n ->
                    { Key = key
                      Text = I18n.t loc ("fac." + key) [ I18n.numberArg "n" (float n) ] }))

    let private cells (beach: Beach) (e: Hour) (s: Shown) (loc: Locale) : AspectCell list =
        let facilities =
            match facilityParts beach.Facilities loc with
            | [] -> []
            | parts -> [ FacilityCounts parts ]

        [ windCell beach e s loc
          WaterTemp(I18n.t loc "cell.water" [ I18n.arg "v" (Fmt.value loc e.SeaTempC " °C" 1) ])
          Waves(Fmt.waves loc e.WaveM (if s.Best then beach.Sea.PeriodS else None))
          Jellyfish(I18n.t loc "cell.jellyfish" [ I18n.arg "level" (levelWord loc e.Jellyfish) ])
          Whales(whalesText beach e loc)
          Quality(Water.summaryText beach.Water loc, beach.Water.Unfit, Water.dotClass beach.Water) ]
        @ facilities

    let ofBeach (beach: Beach) (shown: Shown option) (loc: Locale) : Aspects =
        let head = beach.Name + " · " + headText shown loc

        match Beach.hourEntry beach shown, shown with
        | Some entry, Some s ->
            { Head = head
              Cells = cells beach entry s loc }
        | _ -> { Head = head; Cells = [] }
