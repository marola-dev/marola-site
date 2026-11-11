/// The header, the hour bar, the ranked list, the nav and the SOS panel.
module Marola.Tests.ViewBarTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola
open Marola.Client
open Marola.Tests.ClientSupport

let private count (text: string) (part: string) : int = text.Split(part).Length - 1

let tests =
    testList
        "view bar"
        [ testCase "The list ranks by score and then by distance"
          <| fun () ->
              let model = page ""
              let byScore = ListView.ranked model
              Expect.equal (List.length byScore) 2 "two beaches"
              Expect.isTrue (byScore |> List.forall (fun (_, km) -> km = None)) "no distances by score"
              let nearBrava: Point = { Lat = -27.43; Lon = -48.4 }
              let nearby, _ = Update.update model (Located(Ok nearBrava))

              match ListView.ranked nearby with
              | [ (first, Some a); (_, Some b) ] ->
                  Expect.isTrue (a <= b) "nearest first"
                  Expect.equal first.Name "Praia Brava" "the nearest beach"
              | other -> failtest (sprintf "expected two beaches with distances, got %d" (List.length other))

          testCase "The hour slider reads the selection"
          <| fun () ->
              let model = page ""
              Expect.equal (BarView.hourIndex model) -1 "best hour"
              let moved, _ = Update.update model (HourMoved 1)
              Expect.equal (BarView.hourIndex moved) 1 "second hour"

          testCase "The day buttons name today and tomorrow"
          <| fun () ->
              let text = html [ BarView.header (page "") ]
              Expect.equal (count text "data-day=") 1 "one day button"
              Expect.stringContains text "hoje" "today is named"

          testCase "A beach name with markup stays text"
          <| fun () ->
              let hostile = "<img src=x onerror=alert(1)>"
              let model = page ""

              match model.Board with
              | Some board ->
                  let renamed =
                      match board.Beaches with
                      | first :: rest ->
                          { board with
                              Beaches = { first with Name = hostile } :: rest }
                      | [] -> board

                  let text =
                      html
                          [ ListView.view
                                { model with
                                    Board = Some renamed
                                    Selected = Some hostile } ]

                  Expect.isFalse (text.Contains "<img src=x") "no element made of the name"
                  Expect.stringContains text "&lt;img src=x" "the name is escaped text"
              | None -> failtest "the fixture board is loaded"

          testCase "The SOS panel is hidden until opened"
          <| fun () ->
              let closed = html (SosView.view (page ""))
              Expect.stringContains closed "class=\"sos-panel\"" "panel"
              Expect.stringContains closed "hidden" "hidden"
              Expect.stringContains closed "href=\"tel:193\"" "dials 193"
              let opened, _ = Update.update (page "") SosToggled
              let shown = html (SosView.view opened)
              Expect.isFalse (shown.Contains "aria-labelledby=\"sos-title\" hidden") "open"

          testCase "The nav marks the language on show"
          <| fun () ->
              let text = html (NavView.view (page ""))
              Expect.equal (count text "aria-pressed=\"true\"") 1 "one pressed language"
              Expect.stringContains text "href=\"https://docs.marola.dev/\"" "docs link" ]
