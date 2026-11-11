/// The card of the picked beach. Touch has no hover, so it opens with the tooltip's aspect row
/// (MIP-0009 section 3).
module Marola.Client.CardView

open Marola

let private yes (on: bool) : string = if on then "yes" else "no"

/// Coordinates keep the dot in every language: a decimal comma would collide with the separator.
let fixed4 (n: float) : string =
    // Half away from zero on the magnitude, as the Gleam page rounded; the sign comes back after.
    let scaled = int (System.Math.Floor(abs n * 10000.0 + 0.5))
    let whole = scaled / 10000
    let frac = (string (scaled % 10000)).PadLeft(4, '0')
    let sign = if n < 0.0 && scaled <> 0 then "-" else ""
    sign + string whole + "." + frac

/// A float as a URL carries it: always with a point, as `float.to_string` printed it.
let private plain (n: float) : string =
    let s = string n

    if s.Contains "." || s.Contains "E" || s.Contains "e" then
        s
    else
        s + ".0"

let private headline (model: Model) (b: Beach) (shown: Shown option) : Node<Msg> =
    match shown with
    | None -> Vdom.el "p" [ Vdom.cls "headline past" ] [ Vdom.text (Words.t model "tip.dark") ]
    | Some s ->
        let past =
            match model.Board with
            | Some board -> Board.isPast board s.H
            | None -> false

        let at = Vdom.el "b" [] [ Vdom.text s.H ]

        let words =
            if s.Best then
                Words.withSlot model "card.best_at" [] "h" [ at ]
            else
                Words.withSlot
                    model
                    "card.at_best"
                    [ I18n.arg "best" b.Best.Hour; I18n.arg "score" (string b.Best.Score) ]
                    "h"
                    [ at ]

        let pastTag =
            if past then
                [ Vdom.text " "
                  Vdom.el "span" [ Vdom.cls "past" ] [ Vdom.text (Words.t model "card.past") ] ]
            else
                []

        Vdom.el
            "p"
            [ Vdom.cls "headline" ]
            ([ Vdom.el
                   "span"
                   [ Vdom.cls ("score " + Band.cssClass (Band.ofScore (Some s.Score) b.Water.Unfit)) ]
                   [ Vdom.text (string s.Score + "/100") ]
               Vdom.text " " ]
             @ words
             @ pastTag)

let private why (model: Model) (shown: Shown option) : Node<Msg> =
    match shown |> Option.map (fun s -> Notes.ofShown s model.Loc) with
    | Some(_ :: _ as lines) -> Vdom.el "ul" [] (lines |> List.map (fun n -> Vdom.el "li" [] [ Vdom.text n ]))
    | _ -> Vdom.text (Words.t model "card.good")

let private conditionClass (condition: Condition) : string =
    match condition with
    | Condition.Improper -> "water improper"
    | Condition.Proper -> "water proper"
    | _ -> "water"

let private pointItem (model: Model) (p: WaterPoint) : Node<Msg> =
    let count =
        match p.EnterococciPer100ml with
        | Some n -> [ Vdom.text (", " + Words.ta model "card.enterococci" [ I18n.arg "n" (string n) ]) ]
        | None -> []

    Vdom.el
        "li"
        []
        ([ Vdom.el
               "span"
               [ Vdom.cls (conditionClass p.Condition) ]
               [ Vdom.text (p.Point + " (" + p.Location + "): " + Condition.label p.Condition model.Loc) ]
           Vdom.text (", " + p.SampledOn) ]
         @ count)

let private waterCell (model: Model) (b: Beach) : Node<Msg> list =
    let summary = Water.summaryText b.Water model.Loc

    let points =
        match b.Water.Points with
        | [] -> []
        | points -> [ Vdom.el "ul" [] (points |> List.map (pointItem model)) ]

    let source =
        match b.Water.Source with
        | Some s ->
            [ Vdom.el
                  "small"
                  []
                  (Words.withSlot model "card.source" [] "source" [ Vdom.el "span" [ Vdom.cls "src" ] [ Vdom.text s ] ]) ]
        | None -> []

    [ Vdom.el "span" [ Vdom.cls (if b.Water.Unfit then "unfit" else "water") ] [ Vdom.text summary ] ]
    @ points
    @ source

let private tideText (model: Model) (tide: Tide) : string =
    Words.ta
        model
        (if tide.High then "tide.high" else "tide.low")
        [ I18n.arg "time" tide.Time; I18n.arg "m" (Fmt.signed model.Loc tide.M 1) ]

let private tidesCell (model: Model) (b: Beach) : Node<Msg> list =
    match b.Tides with
    | [] -> [ Vdom.text (Words.t model "tide.none") ]
    | tides ->
        [ Vdom.text ((tides |> List.map (tideText model) |> String.concat ", ") + " ")
          Vdom.el "small" [] [ Vdom.text (Words.t model "tide.hourly") ] ]

let private seaText (model: Model) (b: Beach) : string =
    let sea = b.Sea
    let loc = model.Loc

    let extra (value: float option) (key: string) (unit: string) : string list =
        match value with
        | Some _ -> [ Words.ta model key [ I18n.arg "v" (Fmt.value loc value unit 1) ] ]
        | None -> []

    [ [ Fmt.value loc sea.TempC "°C" 1; Fmt.waves loc sea.WaveM sea.PeriodS ]
      extra sea.SwellM "card.swell" " m"
      extra sea.CurrentKmh "card.current" " km/h" ]
    |> List.concat
    |> String.concat ", "

let private airText (model: Model) (b: Beach) : string =
    let sea = b.Sea
    let loc = model.Loc

    [ [ Fmt.value loc sea.AirTempC "°C" 0
        Words.ta model "cell.wind" [ I18n.arg "v" (Fmt.value loc sea.WindKmh " km/h" 0) ] ]
      (match sea.Uv with
       | Some _ -> [ Words.ta model "card.uv" [ I18n.arg "v" (Fmt.value loc sea.Uv "" 0) ] ]
       | None -> [])
      (match sea.RainPct with
       | Some pct -> [ Words.ta model "card.rain" [ I18n.arg "pct" (Fmt.num loc pct 0) ] ]
       | None -> []) ]
    |> List.concat
    |> String.concat ", "

let private whalesText (model: Model) (b: Beach) : string =
    Words.ta
        model
        "card.whales_now"
        [ I18n.arg "level" (I18n.word model.Loc "lvl." (Level.toString b.Whales.Now))
          I18n.arg "best" (yes b.Whales.Peak.IsSome)
          I18n.arg "peak" (Option.defaultValue "" b.Whales.Peak)
          I18n.arg "season" (yes b.Whales.Season) ]

let private whereCell (b: Beach) : Node<Msg> =
    let lat = plain b.Lat
    let lon = plain b.Lon

    Vdom.el
        "a"
        [ Vdom.attr
              "href"
              ("https://www.openstreetmap.org/?mlat="
               + lat
               + "&mlon="
               + lon
               + "#map=15/"
               + lat
               + "/"
               + lon)
          Vdom.attr "target" "_blank"
          Vdom.attr "rel" "noopener" ]
        [ Vdom.text (fixed4 b.Lat + ", " + fixed4 b.Lon) ]

let private row (model: Model) (key: string) (body: Node<Msg> list) : Node<Msg> list =
    [ Vdom.el "dt" [] [ Vdom.text (Words.t model key) ]; Vdom.el "dd" [] body ]

let private body (model: Model) (b: Beach) : Node<Msg> =
    let shown = Beach.shown b model.Selection
    let tip = Aspects.ofBeach b shown model.Loc

    Vdom.el
        "section"
        [ Vdom.elId "card"; Vdom.cls "card"; Vdom.attr "aria-live" "polite" ]
        [ Vdom.el
              "button"
              [ Vdom.cls "close"
                Vdom.attr "type" "button"
                Vdom.attr "aria-label" (Words.t model "card.close")
                Vdom.onClick CardClosed ]
              [ Vdom.text "×" ]
          Vdom.el "h2" [] [ Vdom.text b.Name ]
          Vdom.el "div" [ Vdom.cls "aspects" ] (AspectsView.children tip)
          headline model b shown
          Vdom.el
              "dl"
              []
              (List.concat
                  [ row model "card.why" [ why model shown ]
                    row model "card.water" (waterCell model b)
                    row
                        model
                        "card.sea"
                        [ Vdom.text (seaText model b + " ")
                          Vdom.el "small" [] [ Vdom.text (Words.ta model "card.at" [ I18n.arg "h" b.Best.Hour ]) ] ]
                    row model "card.tide" (tidesCell model b)
                    row model "card.air" [ Vdom.text (airText model b) ]
                    row model "card.jellyfish" [ Vdom.text (I18n.word model.Loc "lvl." (Level.toString b.Jellyfish)) ]
                    row model "card.whales" [ Vdom.text (whalesText model b) ]
                    row model "card.where" [ whereCell b ] ]) ]

let view (model: Model) : Node<Msg> =
    let picked =
        match model.Selected, model.Board with
        | Some name, Some board -> board.Beaches |> List.tryFind (fun b -> b.Name = name)
        | _ -> None

    match picked with
    | Some b -> body model b
    | None -> Vdom.el "section" ([ Vdom.elId "card"; Vdom.cls "card" ] @ Vdom.hidden true) []
