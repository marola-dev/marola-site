module WaterFileTests exposing (suite)

{-| The area's own sampling points (`data/water/<area>.json`): the file the board cannot carry
because the app matches a point to a beach by name, and the map's dedupe against the board's own
points.
-}

import Effect exposing (Effect(..))
import Expect
import Json.Decode as D
import Model
import Msg exposing (Msg(..))
import Support exposing (loaded, run)
import Test exposing (Test, describe, test)
import Update
import Water exposing (Condition(..))
import WaterFile exposing (WaterFile)


sample : String
sample =
    """
{"schema":1,"area":"floripa","source":"IMA/SC","sampled_on":"2026-11-19","note":null,
 "points":[
  {"point":"Ponto 33","location":"Joaquina","lat":-27.6301,"lon":-48.4479,"condition":"proper","sampled_on":"2026-11-19","enterococci_per_100ml":null,"rain":null},
  {"point":"Ponto 04","location":"Lagoa da Ferrugem","lat":-28.08125,"lon":-48.63206,"condition":"improper","sampled_on":"2026-11-19","enterococci_per_100ml":12,"rain":"Ausente"}
 ]}
"""


decoded : WaterFile
decoded =
    case D.decodeString WaterFile.decoder sample of
        Ok file ->
            file

        Err e ->
            Debug.todo ("bad fixture: " ++ D.errorToString e)


page : String -> Model.Model
page search =
    Tuple.first (loaded search)


attached : String -> WaterFile -> Model.Model
attached area file =
    Tuple.first (run (page "") [ WaterFileLoaded area (Ok file) ])


suite : Test
suite =
    describe "WaterFile"
        [ describe "decoder"
            [ test "reads the file's place and its points" <|
                \_ ->
                    { area = decoded.area, source = decoded.source, sampledOn = decoded.sampledOn, points = List.length decoded.points }
                        |> Expect.equal { area = "floripa", source = "IMA/SC", sampledOn = "2026-11-19", points = 2 }
            , test "a point keeps its verdict and its number" <|
                \_ ->
                    case List.drop 1 decoded.points of
                        p :: _ ->
                            ( p.location, p.condition, p.enterococciPer100ml )
                                |> Expect.equal ( "Lagoa da Ferrugem", Improper, Just 12 )

                        [] ->
                            Expect.fail "the second point is missing"
            ]
        , describe "lagoonWater"
            [ test "keeps the points no beach carries" <|
                \_ ->
                    attached "floripa" decoded
                        |> Model.lagoonWater
                        |> List.map .point
                        |> Expect.equal [ "Ponto 04" ]
            , test "an answer for an area the visitor left is ignored" <|
                \_ ->
                    attached "rio" decoded
                        |> Model.lagoonWater
                        |> Expect.equal []
            ]
        , describe "area switch"
            [ test "asks for the area's own file" <|
                \_ ->
                    Update.update (AreaPicked "rio") (page "") |> Tuple.second |> List.member (FetchWater "rio") |> Expect.equal True
            ]
        ]
