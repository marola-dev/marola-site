/// Shared helpers of the client tests: the fixture board, the trail files, a page that has loaded
/// them through `Update`, and the HTML text of a tree.
module Marola.Tests.ClientSupport

open Marola
open Marola.Client
open Marola.Tests.Support

let fixture () : Board =
    parseOrFail Board.decoder (read "site/fixtures/board.json")

let trailsFile (area: string) : Trails =
    parseOrFail Trails.decoder (read ("app/Client/public/data/trails/" + area + ".json"))

let browser (search: string) (languages: string list) : Env =
    { Path = "/"
      Query = Params.parse search
      Languages = languages
      StoredLanguage = None
      ReducedMotion = false }

let areaNamed (id: string) : Area =
    { Id = id
      Name = "Area " + id
      Lat = -27.6
      Lon = -48.5 }

/// Feeds each message to `Update.update`, keeping the commands of the last one.
let run (model: Model) (messages: Msg list) : Model * Cmd list =
    messages
    |> List.fold (fun (m, _) message -> Update.update m message) (model, [])

/// A page that has loaded its catalogs, an area, a day and the fixture board.
let loaded (search: string) : Model * Cmd list =
    let start, _ = Update.init (browser search [ "pt-BR" ])
    let b = fixture ()

    run
        start
        [ CatalogLoaded(Language.PtBr, Ok(Map.find Language.PtBr (catalog ())))
          CatalogLoaded(Language.En, Ok(Map.find Language.En (catalog ())))
          AreasLoaded(Ok [ areaNamed "floripa"; areaNamed "rio" ])
          LatestLoaded("floripa", Ok [ { Date = b.Day; File = b.Day + ".json" } ])
          BoardLoaded("floripa", b.Day, b.Day + ".json", Ok(Read b)) ]

let page (search: string) : Model = fst (loaded search)

let private voidTags = [ "input"; "img"; "br"; "hr"; "meta"; "link" ]

let rec private nodeHtml (node: Node<'msg>) : string =
    match node with
    | Text t -> Html.escapeHtml t
    | El e ->
        let attrs =
            e.Attrs
            |> List.choose (fun a ->
                match a with
                | Attr(n, "") -> Some(" " + n)
                | Attr(n, v)
                | Prop(n, v) -> Some(" " + n + "=\"" + Html.escapeHtml v + "\"")
                | Flag(n, true) -> Some(" " + n)
                | Flag(_, false)
                | On _ -> None)
            |> String.concat ""

        if List.contains e.Tag voidTags then
            "<" + e.Tag + attrs + ">"
        else
            "<"
            + e.Tag
            + attrs
            + ">"
            + (e.Children |> List.map nodeHtml |> String.concat "")
            + "</"
            + e.Tag
            + ">"

/// The nodes as HTML text: text and attribute values escaped, an empty attribute printed bare.
let html (nodes: Node<'msg> list) : string =
    nodes |> List.map nodeHtml |> String.concat ""

/// How many times `part` occurs in `text`.
let count (text: string) (part: string) : int =
    (text.Split([| part |], System.StringSplitOptions.None)).Length - 1
