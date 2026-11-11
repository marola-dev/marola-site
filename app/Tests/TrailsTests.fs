/// The trail files and the board's fallback, through the decoder.
module Marola.Tests.TrailsTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola
open Marola.Tests.Support

let private file (area: string) : Trails =
    parseOrFail Trails.decoder (read ("app/Client/public/data/trails/" + area + ".json"))

let private isError (result: Result<'a, 'b>) : bool =
    match result with
    | Ok _ -> false
    | Error _ -> true

let tests =
    testList
        "trails"
        [ testCase "Rio groups routes by bairro"
          <| fun () ->
              let rio = file "rio"
              Expect.equal rio.Area "rio" "area"
              Expect.equal rio.IbgeMunicipality (Some "3304557") "ibge"
              Expect.equal rio.Licence (Some "ODbL-1.0") "licence"
              Expect.equal (List.length rio.Groups) 17 "groups"
              Expect.equal (List.length (Trails.routes rio)) 113 "routes"

              Expect.isTrue
                  (rio.Groups
                   |> List.forall (fun g -> g.Bairro.IsSome && not (List.isEmpty g.Routes)))
                  "named, not empty"

          testCase "Rio keeps the sac scale it knows and the one it does not"
          <| fun () ->
              let kinds =
                  Trails.routes (file "rio") |> List.map (fun r -> r.Difficulty) |> List.distinct

              Expect.isTrue (List.contains Difficulty.Hiking kinds) "hiking"
              Expect.isTrue (List.contains Difficulty.MountainHiking kinds) "mountain"
              Expect.isTrue (List.contains Difficulty.Unrated kinds) "unrated"
              Expect.isTrue (List.contains (Difficulty.Unknown "demanding_mountain_hiking") kinds) "unknown"

          testCase "every route of the files has a drawable line and a way"
          <| fun () ->
              for area in [ "rio"; "floripa" ] do
                  let all = Trails.routes (file area)
                  Expect.isFalse (List.isEmpty all) area
                  Expect.isTrue (all |> List.forall (fun r -> not (List.isEmpty (Trails.drawableLines r)))) "lines"
                  Expect.isTrue (all |> List.forall (fun r -> not (List.isEmpty r.OsmWays))) "ways"

          testCase "the first point is lat then lon"
          <| fun () ->
              match Trails.routeAt (file "rio") 0 with
              | Some { Lines = (first :: _) :: _ } ->
                  Expect.isTrue (first.Lat < -20.0 && first.Lat > -25.0) "lat"
                  Expect.isTrue (first.Lon < -40.0 && first.Lon > -45.0) "lon"
              | _ -> failwith "no first point"

          testCase "Salvador has no routes and says why"
          <| fun () ->
              let salvador = file "salvador"
              Expect.isTrue (Trails.isEmpty salvador) "empty"
              Expect.equal salvador.IbgeMunicipality (Some "2927408") "ibge"
              Expect.isTrue salvador.Note.IsSome "note"

          testCase "routeAt finds by position and not past the end"
          <| fun () ->
              let rio = file "rio"
              Expect.isTrue (Trails.routeAt rio 112).IsSome "last"
              Expect.equal (Trails.routeAt rio 113) None "past the end"
              Expect.equal (Trails.routeAt rio (-1)) None "negative"

          testCase "a newer schema is refused"
          <| fun () ->
              let body =
                  "{\"schema\":2,\"area\":\"x\",\"ibge_municipality\":\"1\",\"source\":\"s\",\"licence\":\"l\",\"osm_base\":\"b\",\"bairros\":[]}"

              Expect.isTrue (isError (parse Trails.decoder body)) "schema 2"

          testCase "a missing trails key in a bairro is an error"
          <| fun () ->
              let body =
                  "{\"schema\":1,\"area\":\"x\",\"ibge_municipality\":\"1\",\"source\":\"s\",\"licence\":\"l\",\"osm_base\":\"b\",\"bairros\":[{\"bairro\":\"A\",\"osm_relation\":1}]}"

              Expect.isTrue (isError (parse Trails.decoder body)) "no trails"

          testCase "board trails become one group without a bairro"
          <| fun () ->
              let line = [ { Lat = -27.0; Lon = -48.0 }; { Lat = -27.1; Lon = -48.1 } ]

              let one: Trail =
                  { Name = "Trilha A"
                    LengthKm = 1.5
                    Difficulty = Difficulty.Hiking
                    Surface = Some "dirt"
                    Geometry = line
                    NearBeach = None
                    NearLake = None }

              let lone =
                  { one with
                      Name = "Ponto"
                      Geometry = [ { Lat = 0.0; Lon = 0.0 } ] }

              let result = Trails.fromBoard "floripa" [ one; lone ]
              Expect.equal result.IbgeMunicipality None "no ibge"

              Expect.equal
                  result.Groups
                  [ { Bairro = None
                      Routes =
                        [ { Name = "Trilha A"
                            LengthKm = 1.5
                            Difficulty = Difficulty.Hiking
                            Surface = Some "dirt"
                            OsmWays = []
                            Lines = [ line ] } ] } ]
                  "one group"

          testCase "a board without drawable trails has no group"
          <| fun () -> Expect.equal (Trails.fromBoard "rio" []).Groups [] "none"

          testCase "wayUrl points at the OSM page"
          <| fun () -> Expect.equal (Trails.wayUrl 334779662) "https://www.openstreetmap.org/way/334779662" "url" ]
