/// What the map is told: the JSON of its markers and trails, its configuration and its camera.
module Marola.Tests.MapTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola
open Marola.Client
open Marola.Tests.ClientSupport

let tests =
    testList
        "map"
        [ testCase "the page has one dot per beach in the map JSON"
          <| fun () ->
              let text = MapView.syncJson (page "")
              Expect.equal (count text "\"click\":\"beach\"") 2 "two beaches"

          testCase "the water layer adds every sampling point"
          <| fun () ->
              let quiet = MapView.syncJson (page "")
              let on, _ = Update.update (page "") (LayerPressed Layer.Water)
              let water = MapView.syncJson on
              Expect.isTrue (count water "\"tip_class\":\"\"" > count quiet "\"tip_class\":\"\"") "points added"

          testCase "the map JSON has one part per layer and the trail visibility"
          <| fun () ->
              let text = MapView.syncJson (page "")
              Expect.stringContains text "\"markers\"" "markers"
              Expect.stringContains text "\"trails\":{\"visible\":true,\"selected\":-1}" "trails"

          testCase "a beach name with markup stays a string in the marker JSON"
          <| fun () ->
              let hostile = "<img src=x onerror=alert(1)>"
              let model = page ""
              let board = Option.get model.Board

              let renamed =
                  { board with
                      Beaches =
                          { List.head board.Beaches with
                              Name = hostile }
                          :: List.tail board.Beaches }

              let text = MapView.syncJson { model with Board = Some renamed }

              Expect.stringContains
                  text
                  "\"key\":\"<img src=x onerror=alert(1)>\""
                  "a JSON string, parsed as text by the FFI"

              Expect.isFalse (text.Contains "\"tag\":\"img\"") "no img element"

          testCase "Rio has 113 routes on the map and each has a line"
          <| fun () ->
              let text = TrailGeo.collection (Some(trailsFile "rio")) (page "").Loc
              Expect.equal (count text "\"type\":\"Feature\"") 113 "features"
              Expect.equal (count text "\"color\":\"#") 113 "colours"

          testCase "a route with no drawable line is left out but keeps its id"
          <| fun () ->
              let loc = (page "").Loc

              let route (lines: Point list list) : Route =
                  { Name = "r"
                    LengthKm = 1.0
                    Difficulty = Difficulty.Unrated
                    Surface = None
                    OsmWays = []
                    Lines = lines }

              let line = [ { Lat = 1.0; Lon = 2.0 }; { Lat = 3.0; Lon = 4.0 } ]

              let trails: Trails =
                  { Area = "x"
                    IbgeMunicipality = None
                    Source = "s"
                    Licence = None
                    OsmBase = None
                    Note = None
                    Groups =
                      [ { Bairro = None
                          Routes = [ route [ [ { Lat = 1.0; Lon = 2.0 } ] ]; route [ line ] ] } ] }

              let text = TrailGeo.collection (Some trails) loc
              Expect.equal (count text "\"type\":\"Feature\"") 1 "one feature"
              Expect.stringContains text "\"id\":1" "the second route keeps id 1"

          testCase "without a trail file the board's trails stand in"
          <| fun () ->
              let model =
                  { page "" with
                      TrailsFile = TrailsMissing }

              Expect.isTrue (Model.trails model).IsSome "fallback"

              let pending =
                  { page "" with
                      TrailsFile = TrailsPending }

              Expect.equal (Model.trails pending) None "nothing before the file answers"

          testCase "the flow data is null unless the layer is wind or waves"
          <| fun () -> Expect.equal (FlowData.json (page "")) "null" "off"

          testCase "the flow data carries the field of the wave layer"
          <| fun () ->
              let model = { page "" with Layer = Layer.Waves }
              let text = FlowData.json model
              Expect.stringContains text "\"kind\":\"waves\"" "kind"
              Expect.stringContains text "\"ramp\":[\"#2f5a9e\"" "ramp"

          testCase "camera commands become the JSON the FFI reads"
          <| fun () ->
              Expect.equal (MapJson.cameraJson (Pan(1.5, -2.5))) "{\"kind\":\"pan\",\"lon\":1.5,\"lat\":-2.5}" "pan"
              Expect.stringContains (MapJson.cameraJson (Fit(1.0, 2.0, 3.0, 4.0, 40, 13, true))) "\"max_zoom\":13" "fit"
              Expect.equal (MapJson.cameraJson (MinZoom 0)) "{\"kind\":\"minzoom\",\"zoom\":0}" "min zoom"

          testCase "the map config carries the style and the credit"
          <| fun () ->
              let text = MapJson.mapConfig -48.5 -27.6
              Expect.stringContains text "tiles.openfreemap.org/styles/liberty" "style"
              Expect.stringContains text "OpenStreetMap contributors" "credit"
              Expect.stringContains text "/vendor/maplibre/maplibre-gl-worker.mjs" "worker"

          testCase "the satellite layers count back from the day the board was made"
          <| fun () ->
              let raster = Option.get (Raster.ofLayer Layer.Sst)

              Expect.equal
                  (Raster.id raster "2026-09-07")
                  "GHRSST_L4_MUR_Sea_Surface_Temperature/2026-09-05"
                  "two days back"

              Expect.equal (Raster.ofLayer Layer.Water) None "water has no raster" ]
