/// The trails panel (routes grouped by bairro) and the card of a picked route.
module Marola.Client.TrailsView

open Marola

let private difficultyText (model: Model) (route: Route) : string =
    match route.Difficulty with
    | Difficulty.Hiking -> Words.t model "trails.hiking"
    | Difficulty.MountainHiking -> Words.t model "trails.mountain_hiking"
    | Difficulty.Unrated -> Words.t model "trails.unrated"
    | Difficulty.Unknown raw -> raw

let private lengthText (model: Model) (route: Route) : string =
    Fmt.value model.Loc (Some route.LengthKm) " km" 1

let private difficultyBand (route: Route) : string =
    match route.Difficulty with
    | Difficulty.Hiking -> "c70"
    | Difficulty.MountainHiking -> "c40"
    | _ -> "cna"

let private current (on: bool) : Attr<Msg> =
    Vdom.attr "aria-current" (if on then "true" else "false")

let private routeItem (model: Model) (id: int) (route: Route) : Node<Msg> =
    Vdom.keyed
        (string id)
        (Vdom.el
            "li"
            []
            [ Vdom.el
                  "button"
                  [ Vdom.attr "type" "button"
                    Vdom.attr "data-trail" (string id)
                    Vdom.cls "trail"
                    current (model.TrailSelected = Some id)
                    Vdom.onClick (TrailChosen(id, true)) ]
                  [ Vdom.el
                        "span"
                        [ Vdom.cls ("score " + difficultyBand route) ]
                        [ Vdom.text (difficultyText model route) ]
                    Vdom.text (route.Name + " ")
                    Vdom.el "span" [ Vdom.cls "dist" ] [ Vdom.text (lengthText model route) ] ] ])

/// The groups with the position of each route, which is its id on the map.
let private numbered (groups: Group list) : (Group * int) list =
    groups
    |> List.mapFold (fun first group -> (group, first), first + List.length group.Routes) 0
    |> fst

let private groupView (model: Model) (group: Group, first: int) : Node<Msg> =
    let name = Option.defaultValue (Words.t model "trails.no_bairro") group.Bairro

    Vdom.el
        "section"
        [ Vdom.cls "trail-group" ]
        [ Vdom.el "h3" [] [ Vdom.text name ]
          Vdom.el "ul" [] (group.Routes |> List.mapi (fun i route -> routeItem model (first + i) route)) ]

let private note (found: Trails) : Node<Msg> list =
    match found.Note with
    | Some text -> [ Vdom.el "p" [ Vdom.cls "trail-note" ] [ Vdom.text text ] ]
    | None -> []

/// The footer of the panel: the municipality, and where the lines come from.
let private footer (model: Model) (found: Trails) : Node<Msg> =
    let ibge =
        match found.IbgeMunicipality with
        | Some code -> [ Vdom.el "p" [] [ Vdom.text (Words.ta model "trails.ibge" [ I18n.arg "code" code ]) ] ]
        | None -> []

    let licence =
        match found.Licence with
        | Some l -> ", " + l
        | None -> ""

    Vdom.el
        "footer"
        [ Vdom.cls "trail-foot" ]
        ([ Vdom.el "p" [] [ Vdom.text (Words.ta model "trails.source" [ I18n.arg "source" (found.Source + licence) ]) ] ]
         @ ibge)

let private panelBody (model: Model) : Node<Msg> list =
    match model.TrailsFile, Model.trails model with
    | TrailsPending, _ -> [ Vdom.el "p" [] [ Vdom.text (Words.t model "status.loading") ] ]
    | _, None -> [ Vdom.el "p" [] [ Vdom.text (Words.t model "trails.empty") ] ]
    | _, Some found ->
        if Trails.isEmpty found then
            // An area with no routes says why, never an empty panel.
            let why =
                match found.Note with
                | Some _ -> note found
                | None -> [ Vdom.el "p" [] [ Vdom.text (Words.t model "trails.empty") ] ]

            why @ [ footer model found ]
        else
            note found
            @ (numbered found.Groups |> List.map (groupView model))
            @ [ footer model found ]

let panel (model: Model) : Node<Msg> =
    Vdom.el
        "aside"
        ([ Vdom.elId "trails-panel"
           Vdom.cls "list trails"
           Vdom.attr "aria-label" (Words.t model "flow.trails") ]
         @ Vdom.hidden (model.Panel <> Panel.TrailList))
        ([ Vdom.el "h2" [] [ Vdom.text (Words.t model "flow.trails") ] ]
         @ panelBody model)

let private wayLink (model: Model) (id: int) : Node<Msg> list =
    match Html.safeHref (Trails.wayUrl id) with
    | Some href ->
        [ Vdom.el
              "a"
              [ Vdom.attr "href" href
                Vdom.attr "target" "_blank"
                Vdom.attr "rel" "noopener" ]
              [ Vdom.text (Words.ta model "trails.way" [ I18n.arg "id" (string id) ]) ] ]
    | None -> []

let private row (model: Model) (key: string) (body: Node<Msg> list) : Node<Msg> list =
    [ Vdom.el "dt" [] [ Vdom.text (Words.t model key) ]; Vdom.el "dd" [] body ]

let card (model: Model) (route: Route) : Node<Msg> =
    let surface =
        match route.Surface with
        | Some s -> row model "trails.surface" [ Vdom.text s ]
        | None -> []

    let ways =
        match route.OsmWays with
        | [] -> []
        | ids ->
            ids
            |> List.mapi (fun i id ->
                if i = 0 then
                    wayLink model id
                else
                    Vdom.text " · " :: wayLink model id)
            |> List.concat
            |> row model "trails.ways"

    Vdom.el
        "section"
        [ Vdom.elId "card"; Vdom.cls "card trail-card"; Vdom.attr "aria-live" "polite" ]
        [ Vdom.el
              "button"
              [ Vdom.cls "close"
                Vdom.attr "type" "button"
                Vdom.attr "aria-label" (Words.t model "card.close")
                Vdom.onClick CardClosed ]
              [ Vdom.text "×" ]
          Vdom.el "h2" [] [ Vdom.text route.Name ]
          Vdom.el
              "dl"
              []
              (List.concat
                  [ row model "trails.length" [ Vdom.text (lengthText model route) ]
                    row model "trails.difficulty" [ Vdom.text (difficultyText model route) ]
                    surface
                    ways ]) ]

/// The route the card shows, if one is picked.
let picked (model: Model) : Route option =
    match model.TrailSelected, Model.trails model with
    | Some id, Some found -> Trails.routeAt found id
    | _ -> None
