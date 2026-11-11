/// The footer: the status line, which reads as the board's provenance once a board is on show, and
/// the folds for the sea lore and for the privacy note.
module Marola.Client.FooterView

open Marola

let private yes (on: bool) : string = if on then "yes" else "no"

let private source (name: string) : Node<Msg> =
    let label =
        match Config.sourceLink name with
        | Some href ->
            Vdom.el
                "a"
                [ Vdom.attr "href" href
                  Vdom.attr "target" "_blank"
                  Vdom.attr "rel" "noopener" ]
                [ Vdom.text name ]
        | None -> Vdom.text name

    Vdom.el "span" [ Vdom.cls "src" ] [ label ]

let private intersperse (sep: 'a) (items: 'a list) : 'a list =
    match items with
    | [] -> []
    | first :: rest -> first :: (rest |> List.collect (fun item -> [ sep; item ]))

let private sources (board: Board) : Node<Msg> list =
    [ Some board.Sources.Beaches; Some board.Sources.Forecast; board.Sources.Water ]
    |> List.choose id
    |> List.map source
    |> intersperse (Vdom.text " · ")

/// The generation time as `YYYY-MM-DD HH:MM`.
let private whenText (board: Board) : string =
    let stamp = board.GeneratedAt.Replace("T", " ")
    if stamp.Length > 16 then stamp.Substring(0, 16) else stamp

let private provenance (model: Model) (board: Board) : Node<Msg> list =
    let area =
        match model.Area with
        | Some a -> a.Name
        | None -> board.Area

    Words.withSlot
        model
        "footer.generated"
        [ I18n.arg "when" (whenText board)
          I18n.arg "area" area
          I18n.arg "day" board.Day
          I18n.numberArg "n" (float (List.length board.Beaches)) ]
        "sources"
        (sources board)

/// What the status line says: a load in progress or failed, else the board.
let statusLine (model: Model) : Node<Msg> list =
    match model.Status with
    | Status.Loading name -> [ Vdom.text (Words.ta model "status.loading_named" [ I18n.arg "name" name ]) ]
    | Status.Failed(error, missing) ->
        [ Vdom.text (Words.ta model "fail.load" [ I18n.arg "error" error; I18n.arg "hint" (yes missing) ]) ]
    | Status.NoAreas -> [ Vdom.text (Words.t model "fail.no_areas") ]
    | Status.TooNew schema ->
        [ Vdom.text (
              Words.ta
                  model
                  "fail.schema"
                  [ I18n.arg "got" (string schema)
                    I18n.arg "want" (Board.schemas |> List.map string |> String.concat ", ") ]
          ) ]
    | Status.Idle ->
        match model.Board with
        | Some board -> provenance model board
        | None -> [ Vdom.text (Words.t model "status.loading") ]

let private foldButton (id: string) (label: string) (open': bool) (message: Msg) : Node<Msg> =
    Vdom.el
        "button"
        [ Vdom.attr "type" "button"
          Vdom.cls "fold"
          Vdom.attr "data-fold" id
          Vdom.attr "aria-controls" ("footer-" + id)
          Words.expanded open'
          Vdom.onClick message ]
        [ Vdom.el "span" [ Vdom.cls "pm"; Vdom.attr "aria-hidden" "true" ] []
          Vdom.text label ]

let private lorePanel (model: Model) (found: Lore) : Node<Msg> =
    let link =
        match Html.safeHref found.Source with
        | Some href ->
            [ Vdom.text " "
              Vdom.el
                  "a"
                  [ Vdom.attr "href" href
                    Vdom.attr "target" "_blank"
                    Vdom.attr "rel" "noopener" ]
                  [ Vdom.text ("[" + Words.t model "lore.source" + "]") ] ]
        | None -> []

    let name =
        match found.Kind with
        | LoreKind.Creature -> "fish"
        | _ -> "book"

    Vdom.el
        "p"
        ([ Vdom.elId "footer-lore"; Vdom.cls "fold-panel lore" ]
         @ Vdom.hidden (not model.LoreOpen))
        ([ Words.icon name; Vdom.text (" " + found.Text) ] @ link)

let private blurbPanel (model: Model) : Node<Msg> =
    Vdom.el
        "p"
        ([ Vdom.elId "footer-blurb"; Vdom.cls "fold-panel" ]
         @ Vdom.hidden (not model.BlurbOpen))
        [ Vdom.text (Words.t model "footer.blurb" + " ")
          Vdom.el
              "a"
              [ Vdom.attr "href" Config.repo
                Vdom.attr "target" "_blank"
                Vdom.attr "rel" "noopener" ]
              [ Vdom.text (Words.t model "footer.github") ]
          Vdom.text "." ]

let private loreOf (model: Model) : Lore option =
    model.Board |> Option.bind (fun board -> board.Lore)

let view (model: Model) : Node<Msg> =
    let lore = loreOf model

    let loreFold =
        match lore with
        | Some found ->
            [ foldButton "lore" (Words.t model (Lore.labelKey found.Kind)) model.LoreOpen (FoldToggled LoreFold) ]
        | None -> []

    let folds =
        loreFold
        @ [ foldButton "blurb" (Words.t model "footer.about") model.BlurbOpen (FoldToggled BlurbFold)
            // A placeholder for a feature not built yet: focusable and named, but it opens nothing.
            Vdom.el
                "button"
                [ Vdom.attr "type" "button"
                  Vdom.cls "fold soon"
                  Vdom.attr "aria-disabled" "true"
                  Vdom.attr "aria-describedby" "footer-artists-soon"
                  Vdom.attr "title" (Words.t model "footer.artists_soon") ]
                [ Vdom.el "span" [ Vdom.cls "pm"; Vdom.attr "aria-hidden" "true" ] []
                  Vdom.text (Words.t model "footer.artists") ]
            Vdom.el
                "span"
                [ Vdom.elId "footer-artists-soon"; Vdom.cls "vh" ]
                [ Vdom.text (Words.t model "footer.artists_soon") ] ]

    let panels =
        (match lore with
         | Some found -> [ lorePanel model found ]
         | None -> [])
        @ [ blurbPanel model ]

    Vdom.el
        "footer"
        [ Vdom.elId "footer"; Vdom.cls "footer" ]
        ([ Vdom.el
               "div"
               [ Vdom.cls "footbar" ]
               [ Vdom.el "p" [ Vdom.elId "status" ] (statusLine model)
                 Vdom.el "div" [ Vdom.cls "folds" ] folds ] ]
         @ panels)
