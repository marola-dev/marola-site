module Marola.Client.BarView

open Marola

let private brand (model: Model) : Node<Msg> =
    Vdom.el
        "div"
        [ Vdom.cls "brand" ]
        [ Vdom.el "h1" [] [ Words.icon "brand"; Vdom.text "marola" ]
          Vdom.el "p" [ Vdom.cls "tagline" ] [ Vdom.text (Words.t model "header.tagline") ] ]

let private areaOption (selected: bool) (a: Area) : Node<Msg> =
    Vdom.el
        "option"
        [ Vdom.attr "value" a.Id
          Vdom.attr "title" a.Name
          Vdom.attr "aria-label" a.Name
          Flag("selected", selected) ]
        [ Vdom.text (Config.areaCode a.Id a.Name) ]
    |> Vdom.keyed a.Id

let private insta (model: Model) : Node<Msg> =
    let handle = model.Area |> Option.bind (fun a -> Config.instagram a.Id)

    let city =
        match model.Area with
        | Some a -> a.Name
        | None -> ""

    match handle with
    | None -> Vdom.el "a" ([ Vdom.elId "insta"; Vdom.cls "insta" ] @ Vdom.hidden true) []
    | Some "" ->
        let soon = Words.ta model "insta.soon" [ I18n.arg "city" city ]

        Vdom.el
            "a"
            [ Vdom.elId "insta"
              Vdom.cls "insta soon"
              Vdom.attr "aria-disabled" "true"
              Vdom.attr "aria-label" soon
              Vdom.attr "title" soon ]
            [ Words.icon "instagram"
              Vdom.el "span" [] [ Vdom.text (Words.t model "nav.soon") ] ]
    | Some name ->
        Vdom.el
            "a"
            [ Vdom.elId "insta"
              Vdom.cls "insta"
              Vdom.attr "href" ("https://www.instagram.com/" + name + "/")
              Vdom.attr "target" "_blank"
              Vdom.attr "rel" "noopener"
              Vdom.attr "aria-label" (Words.ta model "insta.label" [ I18n.arg "handle" ("@" + name) ])
              Vdom.attr "title" (Words.ta model "insta.title" [ I18n.arg "city" city ]) ]
            [ Words.icon "instagram"; Vdom.el "span" [] [ Vdom.text ("@" + name) ] ]

/// The month and day of an ISO date.
let private monthDay (date: string) : string =
    if date.Length > 5 then date.Substring 5 else ""

/// A third day and later are named by their date alone, so the picker fits one row on a phone.
let private dayLabel (model: Model) (index: int) (day: DayEntry) : Node<Msg> list =
    let date = Vdom.el "small" [] [ Vdom.text (monthDay day.Date) ]

    match index with
    | 0 -> [ Vdom.text (Words.t model "day.today" + " "); date ]
    | 1 -> [ Vdom.text (Words.t model "day.tomorrow" + " "); date ]
    | _ -> [ Vdom.text (monthDay day.Date) ]

let private days (model: Model) : Node<Msg> =
    Vdom.el
        "div"
        [ Vdom.elId "days"
          Vdom.cls "segmented"
          Vdom.attr "role" "group"
          Vdom.attr "aria-label" (Words.t model "controls.day") ]
        (model.Days
         |> List.mapi (fun i day ->
             Vdom.el
                 "button"
                 ([ Vdom.attr "type" "button"
                    Vdom.attr "data-day" day.Date
                    Vdom.onClick (DayPicked day.Date) ]
                  @ (if model.Day = Some day.Date then [ Vdom.cls "on" ] else []))
                 (dayLabel model i day)
             |> Vdom.keyed day.Date))

let private control
    (model: Model)
    (id: string)
    (iconName: string)
    (label: string)
    (title: string)
    (extra: Attr<Msg> list)
    (message: Msg)
    : Node<Msg> =
    Vdom.el
        "button"
        ([ Vdom.elId id
           Vdom.attr "type" "button"
           Vdom.attr "title" (if title = "" then label else Words.t model title)
           Vdom.onClick message ]
         @ extra)
        [ Words.icon iconName; Vdom.el "span" [] [ Vdom.text label ] ]

let header (model: Model) : Node<Msg> =
    let picked =
        match model.Area with
        | Some a -> a.Id
        | None -> ""

    Vdom.el
        "header"
        [ Vdom.cls "bar" ]
        [ brand model
          Vdom.el
              "div"
              [ Vdom.cls "controls" ]
              [ Vdom.el
                    "select"
                    [ Vdom.elId "area"
                      Vdom.attr "aria-label" (Words.t model "controls.area")
                      Vdom.onChange AreaPicked ]
                    (model.Areas |> List.map (fun a -> areaOption (a.Id = picked) a))
                insta model
                days model
                control
                    model
                    "near"
                    "locate"
                    (Words.t model "controls.near")
                    "controls.near_title"
                    [ Words.pressed (Option.isSome model.Here) ]
                    NearPressed
                control
                    model
                    "sound"
                    "sound"
                    (Words.t model "controls.sound")
                    "controls.sound_title"
                    [ Words.pressed model.SoundOn ]
                    SoundPressed
                control
                    model
                    "toggle-list"
                    "list"
                    (Words.t model "controls.list")
                    ""
                    [ Vdom.attr "aria-controls" "list"
                      Words.expanded (model.Panel = Panel.BeachList) ]
                    ListToggled ] ]

/// The slider's index: -1 is each beach at its own best hour.
let hourIndex (model: Model) : int =
    match model.Selection with
    | Selection.BestHour -> -1
    | Selection.At h -> model.Hours |> List.tryFindIndex ((=) h) |> Option.defaultValue -1

let hourLabel (model: Model) : string =
    match model.Selection, model.Board with
    | Selection.At h, Some b ->
        Words.ta model "hour.at" [ I18n.arg "h" h; I18n.arg "past" (if Board.isPast b h then "yes" else "no") ]
    | _ -> Words.t model "hour.best"

let private chip (band: string) (label: Node<Msg> list) : Node<Msg> =
    Vdom.el "span" [] (Vdom.el "i" [ Vdom.cls band ] [] :: label)

let private legend (model: Model) : Node<Msg> =
    Vdom.el
        "span"
        [ Vdom.cls "legend"; Vdom.attr "aria-hidden" "true" ]
        [ Vdom.el "b" [] [ Vdom.text (Words.t model "legend.score") ]
          Vdom.text " "
          chip "c70" [ Vdom.text "≥70" ]
          chip "c40" [ Vdom.text "40–69" ]
          chip "c1" [ Vdom.text "1–39" ]
          chip "c0" [ Vdom.el "span" [] [ Vdom.text (Words.t model "legend.unfit") ] ]
          chip "cna" [ Vdom.el "span" [] [ Vdom.text (Words.t model "legend.no_data") ] ]
          Vdom.el "span" [ Vdom.cls "wave-key" ] [ Vdom.el "span" [] [ Vdom.text (Words.t model "legend.wave_key") ] ] ]

/// A slider value that is not a number reads as the best hour.
let private parseIndex (value: string) : int =
    match System.Int32.TryParse value with
    | true, n -> n
    | _ -> -1

let hourbar (model: Model) : Node<Msg> =
    Vdom.el
        "div"
        ([ Vdom.elId "hourbar"; Vdom.cls "hourbar" ]
         @ Vdom.hidden (List.isEmpty model.Hours))
        [ Vdom.el
              "label"
              [ Vdom.attr "for" "hour" ]
              [ Vdom.el "span" [ Vdom.elId "hour-label" ] [ Vdom.text (hourLabel model) ] ]
          Vdom.el
              "input"
              [ Vdom.elId "hour"
                Vdom.attr "type" "range"
                Vdom.attr "min" "-1"
                Vdom.attr "max" (string (List.length model.Hours - 1))
                Vdom.attr "step" "1"
                Prop("value", string (hourIndex model))
                Vdom.attr "aria-label" (Words.t model "hour.slider")
                Vdom.onInput (parseIndex >> HourMoved) ]
              []
          legend model ]
