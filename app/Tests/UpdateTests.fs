/// The state machine against the real fixture board and catalogs: what a visitor's action changes,
/// and which commands it asks for.
module Marola.Tests.UpdateTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola
open Marola.Client
open Marola.Tests.Support
open Marola.Tests.ClientSupport

let private has (commands: Cmd list) (wanted: Cmd) : bool = List.contains wanted commands

let private syncs (commands: Cmd list) : string list =
    commands
    |> List.choose (fun c ->
        match c with
        | SyncMap text -> Some text
        | _ -> None)

let private isFit (c: Cmd) : bool =
    match c with
    | MoveCamera(Fit _) -> true
    | _ -> false

let private isPan (c: Cmd) : bool =
    match c with
    | MoveCamera(Pan _) -> true
    | _ -> false

let private withTrails (search: string) : Model =
    let model = page search
    fst (Update.update model (TrailsFileLoaded("floripa", Ok(trailsFile "floripa"))))

let tests =
    testList
        "update"
        [ testCase "init reads the links it understands"
          <| fun () ->
              let model, commands =
                  Update.init (browser "?layer=water&beaches=0&lang=en&trails=0" [ "pt-BR" ])

              Expect.equal model.Layer Layer.Water "layer"
              Expect.isFalse model.ShowBeaches "beaches"
              Expect.isFalse model.ShowTrails "trails"
              Expect.equal model.Loc.Language Language.En "language"
              Expect.equal commands [ FetchCatalog Language.PtBr; FetchCatalog Language.En ] "catalogs"

          testCase "init ignores a layer whose button is off"
          <| fun () ->
              let model, _ = Update.init (browser "?layer=wind" [])
              Expect.equal model.Layer Layer.Off "wind is off"
              let model, _ = Update.init (browser "?layer=nonsense" [])
              Expect.equal model.Layer Layer.Off "unknown"

          testCase "the page waits for both catalogs, then fetches the areas"
          <| fun () ->
              let start, _ = Update.init (browser "" [ "en-US" ])
              let one, first = Update.update start (CatalogLoaded(Language.PtBr, Ok Map.empty))
              Expect.equal first [] "nothing yet"
              Expect.equal one.CatalogsPending 1 "one left"
              let both, second = Update.update one (CatalogLoaded(Language.En, Ok Map.empty))
              Expect.equal both.CatalogsPending 0 "none left"
              Expect.isTrue (has second FetchAreas) "areas"

          testCase "a catalog that failed is said in the footer, and the page still goes on"
          <| fun () ->
              let start, _ = Update.init (browser "" [])

              let after, _ =
                  Update.update start (CatalogLoaded(Language.En, Error(HttpError 500)))

              Expect.equal after.Status (Status.Failed("500 i18n/en.json", false)) "status"
              Expect.equal after.CatalogsPending 1 "counted"

          testCase "the area in the link wins over the first"
          <| fun () ->
              let start, _ = Update.init (browser "?area=rio" [])

              let model, commands =
                  Update.update start (AreasLoaded(Ok [ areaNamed "floripa"; areaNamed "rio" ]))

              Expect.equal model.Area (Some(areaNamed "rio")) "area"
              Expect.isTrue (has commands (FetchLatest "rio")) "latest"
              Expect.isTrue (has commands (FetchTrails "rio")) "trails"
              Expect.isTrue (has commands (InitMap(-48.5, -27.6))) "map"
              Expect.equal model.Map MapLoading "loading"
              Expect.equal (Params.get model.Query "area") (Some "rio") "query"

          testCase "no areas is a status, not a crash"
          <| fun () ->
              let start, _ = Update.init (browser "" [])
              let model, _ = Update.update start (AreasLoaded(Ok []))
              Expect.equal model.Status Status.NoAreas "status"

          testCase "the newest day loads unless the link names one"
          <| fun () ->
              let days =
                  [ { Date = "2026-09-06"; File = "a.json" }
                    { Date = "2026-09-07"; File = "b.json" } ]

              let start, _ = Update.init (browser "" [])
              let area = AreasLoaded(Ok [ areaNamed "floripa" ])
              let _, commands = run start [ area; LatestLoaded("floripa", Ok days) ]
              Expect.isTrue (has commands (FetchBoard("floripa", "2026-09-07", "b.json"))) "newest"
              let linked, _ = Update.init (browser "?day=2026-09-06" [])
              let _, commands = run linked [ area; LatestLoaded("floripa", Ok days) ]
              Expect.isTrue (has commands (FetchBoard("floripa", "2026-09-06", "a.json"))) "linked"

          testCase "an answer for an area the visitor left is dropped"
          <| fun () ->
              let model, _ = loaded ""
              let stale = fixture ()

              let after, commands =
                  Update.update model (BoardLoaded("rio", stale.Day, "x.json", Ok(Read stale)))

              Expect.equal after model "same model"
              Expect.equal commands [] "no commands"

          testCase "a board newer than the page is reported"
          <| fun () ->
              let model, _ = loaded ""

              let after, _ =
                  Update.update model (BoardLoaded("floripa", (fixture ()).Day, "x.json", Ok(Newer 9)))

              Expect.equal after.Status (Status.TooNew 9) "status"

          testCase "a failed board says the status and the path"
          <| fun () ->
              let model, _ = loaded ""

              let after, _ =
                  Update.update model (BoardLoaded("floripa", (fixture ()).Day, "x.json", Error(HttpError 404)))

              Expect.equal after.Status (Status.Failed("404 data/floripa/x.json", true)) "missing file"

          testCase "a loaded board shows its beaches and fits the map once"
          <| fun () ->
              let model, commands = loaded ""
              Expect.equal model.Status Status.Idle "idle"
              Expect.isFalse (List.isEmpty model.Hours) "hours"
              Expect.isTrue model.Fitted "fitted"
              Expect.isTrue (List.exists isFit commands) "fit"

              match syncs commands with
              | [ text ] ->
                  Expect.stringContains text "Praia da Joaquina" "first beach"
                  Expect.stringContains text "Praia Brava" "second beach"
              | other -> failwith ("expected one sync, got " + string (List.length other))

              // The second board of the same area keeps the view the visitor has.
              let b = fixture ()

              let again, more =
                  Update.update model (BoardLoaded("floripa", b.Day, "x.json", Ok(Read b)))

              Expect.isFalse (List.exists isFit more) "no second fit"
              Expect.isTrue again.Fitted "still fitted"

          testCase "a beach in the link opens its card"
          <| fun () ->
              let model, _ = loaded "?beach=Praia%20Brava"
              Expect.equal model.Selected (Some "Praia Brava") "known beach"
              let model, _ = loaded "?beach=Nowhere"
              Expect.equal model.Selected None "unknown beach"

          testCase "picking and closing a beach keeps the link in step"
          <| fun () ->
              let model, _ = loaded ""
              let picked, commands = Update.update model (BeachPicked("Praia Brava", true))
              Expect.equal picked.Selected (Some "Praia Brava") "selected"
              Expect.isTrue (has commands (ReplaceUrl("/", Params.toString picked.Query))) "url"
              Expect.equal (Params.get picked.Query "beach") (Some "Praia Brava") "query"
              Expect.isTrue (List.exists isPan commands) "list pans the map"
              let closed, _ = Update.update picked CardClosed
              Expect.equal closed.Selected None "closed"
              Expect.equal (Params.get closed.Query "beach") None "query cleared"

          testCase "closing with nothing open changes nothing"
          <| fun () ->
              let model, _ = loaded ""
              let after, commands = Update.update model CardClosed
              Expect.equal after model "same"
              Expect.equal commands [] "none"

          testCase "the slider moves between best hour and a clock hour"
          <| fun () ->
              let model, _ = loaded ""
              let moved, _ = Update.update model (HourMoved 0)
              Expect.equal moved.Selection (Selection.At(List.head model.Hours)) "first hour"
              let back, _ = Update.update moved (HourMoved -1)
              Expect.equal back.Selection Selection.BestHour "best hour"
              let past, _ = Update.update moved (HourMoved 999)
              Expect.equal past.Selection Selection.BestHour "out of range is the best hour"

          testCase "a layer button that is off does nothing"
          <| fun () ->
              let model, _ = loaded ""
              let after, commands = Update.update model (LayerPressed Layer.Wind)
              Expect.equal after model "same"
              Expect.equal commands [] "none"

          testCase "pressing the water layer twice turns it off"
          <| fun () ->
              let model, _ = loaded ""
              let on, _ = Update.update model (LayerPressed Layer.Water)
              Expect.equal on.Layer Layer.Water "on"
              Expect.equal (Params.get on.Query "layer") (Some "water") "query"
              let off, _ = Update.update on (LayerPressed Layer.Water)
              Expect.equal off.Layer Layer.Off "off"

          testCase "the beach list and the trail panel never share the edge"
          <| fun () ->
              let model, _ = loaded ""
              let listOpen, _ = Update.update model ListToggled
              Expect.equal listOpen.Panel Panel.BeachList "list"
              let trailsOpen, _ = Update.update listOpen TrailPanelToggled
              Expect.equal trailsOpen.Panel Panel.TrailList "trails replace the list"
              let closed, _ = Update.update trailsOpen TrailPanelToggled
              Expect.equal closed.Panel Panel.Closed "closed"

          testCase "a style error before the map loads opens the list"
          <| fun () ->
              let model, _ = loaded ""
              let failed, _ = Update.update model (MapEvent("error", "style"))
              Expect.equal failed.Map (MapFailed "map.failed") "failed"
              Expect.equal failed.Panel Panel.BeachList "list"

          testCase "an error after the map is ready is ignored"
          <| fun () ->
              let model, _ = loaded ""
              let ready, _ = Update.update model (MapEvent("ready", ""))
              let after, _ = Update.update ready (MapEvent("error", "tile"))
              Expect.equal after.Map MapReady "still ready"
              Expect.equal after.Panel Panel.Closed "no panel"

          testCase "a click on a dot picks the beach without panning"
          <| fun () ->
              let model, _ = loaded ""
              let picked, commands = Update.update model (MapEvent("beach", "Praia Brava"))
              Expect.equal picked.Selected (Some "Praia Brava") "selected"
              Expect.isFalse (List.exists isPan commands) "no pan"

          testCase "a click on the empty map closes the cards"
          <| fun () ->
              let model, _ = loaded "?beach=Praia%20Brava"
              let after, _ = Update.update model (MapEvent("click", ""))
              Expect.equal after.Selected None "closed"

          testCase "picking a language stores it and retitles the page"
          <| fun () ->
              let model, _ = loaded ""
              let after, commands = Update.update model (LanguagePicked Language.En)
              Expect.equal after.Loc.Language Language.En "language"
              Expect.equal (Params.get after.Query "lang") (Some "en") "query"
              Expect.isTrue (has commands (StoreLanguage Language.En)) "stored"
              Expect.isTrue (has commands (SetDocument("en", "marola: sea conditions at every beach"))) "title"
              Expect.isFalse (List.isEmpty (syncs commands)) "map redrawn in the new language"

              Expect.isFalse
                  (List.exists
                      (fun c ->
                          match c with
                          | FetchBoard _ -> true
                          | _ -> false)
                      commands)
                  "no fetch"

          testCase "the same language again changes nothing"
          <| fun () ->
              let model, _ = loaded ""
              let after, commands = Update.update model (LanguagePicked Language.PtBr)
              Expect.equal after model "same"
              Expect.equal commands [] "none"

          testCase "a picked route closes the beach card"
          <| fun () ->
              let model = withTrails "?beach=Praia%20Brava"
              let picked, _ = Update.update model (TrailChosen(0, true))
              Expect.equal picked.TrailSelected (Some 0) "route"
              Expect.equal picked.Selected None "beach closed"
              Expect.equal (Params.get picked.Query "beach") None "query cleared"

          testCase "a route id that does not exist changes nothing"
          <| fun () ->
              let model = withTrails ""
              let after, commands = Update.update model (TrailChosen(99999, true))
              Expect.equal after model "same"
              Expect.equal commands [] "none"

          testCase "a missing trail file falls back to the board"
          <| fun () ->
              let model, _ = loaded ""
              let after, _ = Update.update model (TrailsFileLoaded("floripa", Error NetworkError))
              Expect.equal after.TrailsFile TrailsMissing "missing"
              Expect.isTrue (Model.trails after).IsSome "the board's own trails"

          testCase "the location answer ranks by distance and opens the list"
          <| fun () ->
              let model, _ = loaded ""
              let here = { Lat = -27.6; Lon = -48.5 }
              let after, _ = Update.update model (Located(Ok here))
              Expect.equal after.Here (Some here) "here"
              Expect.equal after.Panel Panel.BeachList "list"
              let gone, _ = Update.update after NearPressed
              Expect.equal gone.Here None "pressed again forgets it"

          testCase "a refused location is said in the page's language"
          <| fun () ->
              let model, _ = loaded ""
              let _, commands = Update.update model (Located(Error "denied"))
              Expect.equal commands [ Alert(I18n.t model.Loc "near.denied" []) ] "alert"

          testCase "the sound button flips the flag and a failure turns it off"
          <| fun () ->
              let model, _ = loaded ""
              let on, commands = Update.update model SoundPressed
              Expect.isTrue on.SoundOn "on"
              Expect.equal commands [ Sound true ] "command"
              let failed, _ = Update.update on SoundFailed
              Expect.isFalse failed.SoundOn "off"

          testCase "the SOS panel opens, and closing it gives the focus back"
          <| fun () ->
              let model, _ = loaded ""
              let on, _ = Update.update model SosToggled
              Expect.isTrue on.SosOpen "open"
              let off, commands = Update.update on SosClosed
              Expect.isFalse off.SosOpen "closed"
              Expect.equal commands [ Focus "sos" ] "focus"
              let same, none = Update.update off SosClosed
              Expect.equal same off "closing a closed panel"
              Expect.equal none [] "no focus"

          testCase "the folds toggle on their own"
          <| fun () ->
              let model, _ = loaded ""
              let lore, _ = Update.update model (FoldToggled LoreFold)
              Expect.isTrue lore.LoreOpen "lore"
              Expect.isFalse lore.BlurbOpen "blurb untouched"
              let blurb, _ = Update.update lore (FoldToggled BlurbFold)
              Expect.isTrue blurb.BlurbOpen "blurb"

          testCase "the beach and trail toggles write the link and redraw"
          <| fun () ->
              let model, _ = loaded ""
              let off, commands = Update.update model BeachesToggled
              Expect.isFalse off.ShowBeaches "beaches"
              Expect.equal (Params.get off.Query "beaches") (Some "0") "query"
              Expect.isFalse (List.isEmpty (syncs commands)) "synced"
              let on, _ = Update.update off BeachesToggled
              Expect.equal (Params.get on.Query "beaches") (Some "1") "back"
              let noTrails, _ = Update.update model TrailsToggled
              Expect.isFalse noTrails.ShowTrails "trails"

          testCase "picking an area starts afresh and fetches its data"
          <| fun () ->
              let model, _ = loaded "?beach=Praia%20Brava"
              let after, commands = Update.update model (AreaPicked "rio")
              Expect.equal after.Area (Some(areaNamed "rio")) "area"
              Expect.equal after.Board None "board cleared"
              Expect.equal after.Selected None "beach cleared"
              Expect.equal (Params.get after.Query "beach") None "beach out of the link"
              Expect.isTrue (has commands (FetchLatest "rio")) "latest"

              Expect.isFalse
                  (List.exists
                      (fun c ->
                          match c with
                          | InitMap _ -> true
                          | _ -> false)
                      commands)
                  "the map exists"

              Expect.isTrue
                  (List.exists
                      (fun c ->
                          match c with
                          | MoveCamera(Jump _) -> true
                          | _ -> false)
                      commands)
                  "jump"

              let unknown, none = Update.update model (AreaPicked "nowhere")
              Expect.equal unknown model "unknown area"
              Expect.equal none [] "no commands" ]
