module Marola.Client.ListView

open Marola

/// Each beach with its distance when the visitor shared a position.
let ranked (model: Model) : (Beach * float option) list =
    let beaches = Model.beaches model

    match model.Here with
    | Some here -> Rank.byDistance beaches here |> List.map (fun (b, km) -> b, Some km)
    | None -> Rank.byScore beaches model.Selection |> List.map (fun b -> b, None)

let private row (model: Model) (beach: Beach, km: float option) : Node<Msg> =
    let shown = Beach.shown beach model.Selection
    let score = shown |> Option.map (fun s -> s.Score)

    let chip =
        match score with
        | Some s -> string s
        | None -> "–"

    let hour =
        match shown with
        | Some s -> s.H
        | None -> Words.t model "list.dark"

    let summary = Water.summaryText beach.Water model.Loc

    let waterSpan =
        match beach.Water.Unfit, beach.Water.Points with
        | true, _ ->
            [ Vdom.text " "
              Vdom.el "span" [ Vdom.cls "water unfit" ] [ Vdom.text summary ] ]
        | false, _ :: _ -> [ Vdom.text " "; Vdom.el "span" [ Vdom.cls "water" ] [ Vdom.text summary ] ]
        | false, [] -> []

    let distance =
        match km with
        | Some d ->
            [ Vdom.text " "
              Vdom.el "span" [ Vdom.cls "dist" ] [ Vdom.text (Fmt.num model.Loc d 1 + " km") ] ]
        | None -> []

    Vdom.el
        "li"
        [ Vdom.attr "data-name" beach.Name
          Vdom.attr "tabindex" "0"
          Vdom.attr "role" "button"
          Vdom.onClick (BeachPicked(beach.Name, true))
          Vdom.onActivate (BeachPicked(beach.Name, true)) ]
        ([ Vdom.el
               "span"
               [ Vdom.cls ("score " + Band.cssClass (Band.ofScore score beach.Water.Unfit)) ]
               [ Vdom.text chip ]
           Vdom.text (beach.Name + " ")
           Vdom.el "span" [ Vdom.cls "dist" ] [ Vdom.text hour ] ]
         @ distance
         @ waterSpan)
    |> Vdom.keyed beach.Name

let view (model: Model) : Node<Msg> =
    Vdom.el
        "aside"
        ([ Vdom.elId "list"; Vdom.cls "list" ]
         @ Vdom.hidden (model.Panel <> Panel.BeachList))
        [ Vdom.el "ol" [] (ranked model |> List.map (row model)) ]
