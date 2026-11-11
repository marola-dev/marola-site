namespace Marola.Client

open Marola

/// The aspect cells of a beach: the tooltip over its dot and the first rows of its card. Every icon
/// is followed by its word: the icon is decoration, the word is the reading.
module AspectsView =

    let private reading (icon: string) (text: Node<'msg> list) : Node<'msg> =
        Vdom.el "span" [] (Icons.icon icon :: Vdom.text " " :: text)

    let private cell (c: AspectCell) : Node<'msg> =
        match c with
        | Wind(text, None) -> reading "wind" [ Vdom.text text ]
        | Wind(text, Some direction) ->
            reading
                "wind"
                [ Vdom.text (text + " ")
                  Vdom.el "abbr" [ Vdom.cls "dir" ] [ Vdom.text direction ] ]
        | WaterTemp text -> reading "thermometer" [ Vdom.text text ]
        | Waves text -> reading "waves" [ Vdom.text text ]
        | Jellyfish text -> reading "jellyfish" [ Vdom.text text ]
        | Whales text -> reading "fish" [ Vdom.text text ]
        | Quality(text, unfit, dotClass) ->
            Vdom.el
                "span"
                [ Vdom.cls (if unfit then "wide unfit" else "wide water") ]
                [ Vdom.el "i" [ Vdom.cls dotClass ] []; Vdom.text (" " + text) ]
        | FacilityCounts parts ->
            Vdom.el
                "span"
                [ Vdom.cls "wide facilities" ]
                (parts
                 |> List.mapi (fun i part ->
                     let item = [ Icons.icon part.Key; Vdom.text (" " + part.Text) ]
                     if i = 0 then item else Vdom.text " · " :: item)
                 |> List.concat)

    /// The head line, then the grid of readings; no grid when the beach is dark.
    let children (aspects: Aspects) : Node<'msg> list =
        let head = Vdom.el "div" [ Vdom.cls "head" ] [ Vdom.text aspects.Head ]

        match aspects.Cells with
        | [] -> [ head ]
        | cells -> [ head; Vdom.el "div" [ Vdom.cls "grid" ] (List.map cell cells) ]
