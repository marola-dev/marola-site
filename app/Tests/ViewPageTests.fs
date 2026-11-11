/// The card, the footer, the layer rail, the trails panel and the page, as the views draw them.
module Marola.Tests.ViewPageTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola
open Marola.Client
open Marola.Tests.ClientSupport

let private count (text: string) (part: string) : int = (text.Split part).Length - 1

let private pageHtml (model: Model) : string = html (Page.view model)

/// Whether any node of the tree, text included, satisfies `test`.
let rec private exists (test: Node<Msg> -> bool) (node: Node<Msg>) : bool =
    test node
    || (match node with
        | El e -> List.exists (exists test) e.Children
        | Text _ -> false)

let private isTag (tag: string) (node: Node<Msg>) : bool =
    match node with
    | El e -> e.Tag = tag
    | Text _ -> false

let private onlyText (expected: string) (children: Node<Msg> list) : bool =
    match children with
    | [ Text found ] -> found = expected
    | _ -> false

let private withTrails (found: Trails) (panel: Panel) : Model =
    { page "" with
        TrailsFile = TrailsLoaded found
        Panel = panel }

let tests =
    testList
        "view page"
        [ testCase "coordinates keep the dot in every language"
          <| fun () ->
              Expect.equal (CardView.fixed4 -27.6296) "-27.6296" "negative"
              Expect.equal (CardView.fixed4 -27.5) "-27.5000" "padded"
              Expect.equal (CardView.fixed4 0.00004) "0.0000" "rounds to zero"
              Expect.equal (CardView.fixed4 -0.00004) "0.0000" "no sign on zero"

          testCase "the footer names the board once it is on show"
          <| fun () ->
              let text = html (FooterView.statusLine (page ""))
              Expect.stringContains text "Open-Meteo" "source"
              Expect.stringContains text "2 praias" "count"
              Expect.stringContains text "https://open-meteo.com/" "link"

          testCase "the footer says what failed"
          <| fun () ->
              let model =
                  { page "" with
                      Status = Status.Failed("404 data/x.json", true) }

              Expect.stringContains (html (FooterView.statusLine model)) "404 data/x.json" "error"

          testCase "a beach name with markup stays text"
          <| fun () ->
              let hostile = "<img src=x onerror=alert(1)>"
              let model = page ""

              let renamed =
                  match model.Board with
                  | Some b ->
                      match b.Beaches with
                      | first :: rest ->
                          { b with
                              Beaches = { first with Name = hostile } :: rest }
                      | [] -> failwith "the fixture has no beaches"
                  | None -> failwith "the fixture has no board"

              let shown =
                  { model with
                      Board = Some renamed
                      Selected = Some hostile }

              let nodes = Page.view shown
              // The tree holds the name as one text node and builds no element from it.
              Expect.isFalse (nodes |> List.exists (exists (isTag "img"))) "no img element"

              let heading =
                  nodes
                  |> List.exists (
                      exists (fun n ->
                          match n with
                          | El e -> e.Tag = "h2" && onlyText hostile e.Children
                          | Text _ -> false)
                  )

              Expect.isTrue heading "the name is a text node of the card heading"
              let text = html nodes
              Expect.isFalse (text.Contains "<img src=x") "no raw markup"
              Expect.stringContains text "&lt;img src=x" "escaped"

          testCase "the card opens for the picked beach and nothing else"
          <| fun () ->
              let closed = pageHtml (page "")
              Expect.equal (count closed "class=\"card\" hidden") 1 "hidden card"
              let open', _ = run (page "") [ BeachPicked("Praia Brava", false) ]
              let text = pageHtml open'
              Expect.stringContains text "<h2>Praia Brava</h2>" "heading"
              Expect.equal (count text "class=\"close\"") 1 "one close button"

          testCase "the layer buttons mark the one on show"
          <| fun () ->
              let on, _ = run (page "") [ LayerPressed Layer.Water ]
              let text = pageHtml on
              Expect.stringContains text "data-layer=\"water\"" "water button"
              Expect.equal (count text "data-layer=") 7 "seven layer buttons"
              Expect.isTrue (count text "disabled" >= 7) "the unbuilt ones are disabled"
              Expect.stringContains text "layer-water" "main class"

          testCase "a failed map hides the rail and says why"
          <| fun () ->
              let failed, _ = run (page "") [ MapEvent("error", "style") ]
              let text = pageHtml failed
              Expect.stringContains text "o mapa não abriu neste navegador" "the note"
              Expect.isFalse (text.Contains "id=\"flow\"") "no rail"
              Expect.equal failed.Panel Panel.BeachList "the list opens"

          testCase "Salvador has no routes and a note"
          <| fun () ->
              let found = trailsFile "salvador"
              Expect.isTrue (Trails.isEmpty found) "no routes"
              Expect.isTrue found.Note.IsSome "a note"
              let text = pageHtml (withTrails found Panel.TrailList)

              match found.Note with
              | Some note ->
                  Expect.stringContains text (note.Substring(0, min 20 note.Length)) "the note is on the panel"
              | None -> ()

              Expect.isFalse (text.Contains "data-trail=") "no route button"

          testCase "the trail panel groups routes by bairro with the municipality"
          <| fun () ->
              let text = pageHtml (withTrails (trailsFile "rio") Panel.TrailList)
              Expect.equal (count text "data-trail=") 113 "routes"
              Expect.equal (count text "class=\"trail-group\"") 17 "groups"
              Expect.stringContains text "3304557" "municipality"

          testCase "a picked route links its OSM ways"
          <| fun () ->
              let model =
                  { page "" with
                      TrailsFile = TrailsLoaded(trailsFile "floripa") }

              let picked, _ = run model [ TrailChosen(0, true) ]

              match TrailsView.picked picked with
              | Some route ->
                  let text = html [ TrailsView.card picked route ]

                  match route.OsmWays with
                  | way :: _ ->
                      Expect.stringContains text ("https://www.openstreetmap.org/way/" + string way) "way link"
                  | [] -> failwith "the first route has no OSM way"

                  Expect.stringContains text "rel=\"noopener\"" "noopener"
              | None -> failwith "no route picked"

          testCase "without a trail file the board trails stand in"
          <| fun () ->
              let missing =
                  { page "" with
                      TrailsFile = TrailsMissing }

              Expect.isTrue (Model.trails missing).IsSome "the board's trails"

              let pending =
                  { page "" with
                      TrailsFile = TrailsPending }

              Expect.isTrue (Model.trails pending).IsNone "nothing while pending" ]
