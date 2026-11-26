module WaterFileTests exposing (suite)

{-| The area's own sampling points (`data/water/<area>.json`): the file the board cannot carry
because the app matches a point to a beach by name, and the map's dedupe against the board's own
points.
-}

import Effect exposing (Effect(..))
import Expect
import Json.Decode as D
import Layer
import MapView
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
{"schema":1,"area":"floripa","source":"IMA/SC","sampled_on":"2026-11-19","next_bulletin":"2026-12-18","note":null,
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
                    { area = decoded.area, source = decoded.source, sampledOn = decoded.sampledOn, nextBulletin = decoded.nextBulletin, points = List.length decoded.points }
                        |> Expect.equal { area = "floripa", source = "IMA/SC", sampledOn = "2026-11-19", nextBulletin = Just "2026-12-18", points = 2 }
            , test "a point keeps its verdict and its number" <|
                \_ ->
                    case List.drop 1 decoded.points of
                        p :: _ ->
                            ( p.location, p.condition, p.enterococciPer100ml )
                                |> Expect.equal ( "Lagoa da Ferrugem", Improper, Just 12 )

                        [] ->
                            Expect.fail "the second point is missing"
            ]
        , describe "same"
            [ test "a rounded coordinate is the same sample" <|
                \_ ->
                    case List.head decoded.points of
                        Just p ->
                            WaterFile.same p { p | lat = p.lat + 0.0001, lon = p.lon + 0.0001 }
                                |> Expect.equal True

                        Nothing ->
                            Expect.fail "the fixture lost its points"
            , test "an agency code at another place is not the same sample" <|
                \_ ->
                    case List.drop 1 decoded.points |> List.head of
                        Just p ->
                            WaterFile.same p { p | lat = p.lat + 0.5 }
                                |> Expect.equal False

                        Nothing ->
                            Expect.fail "the fixture lost its second point"
            ]
        , describe "lagoonWater"
            [ test "keeps the points no beach carries" <|
                \_ ->
                    attached "floripa" decoded
                        |> Model.lagoonWater
                        |> List.map .point
                        |> Expect.equal [ "Ponto 04" ]
            , test "the same agency code is one sample, even when the board rounds it elsewhere" <|
                \_ ->
                    let
                        shifted =
                            { decoded
                                | points =
                                    List.map
                                        (\p ->
                                            if p.point == "Ponto 33" then
                                                { p | lat = p.lat + 0.01 }

                                            else
                                                p
                                        )
                                        decoded.points
                            }
                    in
                    attached "floripa" shifted
                        |> Model.lagoonWater
                        |> List.map .point
                        |> Expect.equal [ "Ponto 04" ]
            , test "an answer for an area the visitor left is ignored" <|
                \_ ->
                    attached "rio" decoded
                        |> Model.lagoonWater
                        |> Expect.equal []
            ]
        , describe "waterPoints"
            [ test "the map draws a sample once, even when the board carries it twice" <|
                \_ ->
                    let
                        base =
                            attached "floripa" decoded

                        model =
                            { base | layer = Layer.Water }

                        doubled =
                            case model.board of
                                Just board ->
                                    case board.beaches of
                                        b :: _ ->
                                            { model | board = Just { board | beaches = board.beaches ++ [ b ] } }

                                        [] ->
                                            model

                                Nothing ->
                                    model
                    in
                    MapView.waterPoints doubled
                        |> List.map .point
                        |> Expect.equal [ "Ponto 33", "Ponto 12", "Ponto 04" ]
            ]
        , describe "beaches"
            [ test "a board with no water for a beach takes the file's point for it" <|
                \_ ->
                    let
                        base =
                            attached "floripa" decoded

                        model =
                            { base | layer = Layer.Water }

                        emptied =
                            case model.board of
                                Just board ->
                                    case board.beaches of
                                        b :: rest ->
                                            let
                                                water =
                                                    b.water

                                                emptyWater =
                                                    { water | points = [], summary = "no data", unfit = False }
                                            in
                                            { model
                                                | board =
                                                    Just
                                                        { board
                                                            | beaches =
                                                                { b | water = emptyWater }
                                                                    :: rest
                                                        }
                                            }

                                        [] ->
                                            model

                                Nothing ->
                                    model
                    in
                    case Model.beaches emptied |> List.head of
                        Just b ->
                            ( List.map .point b.water.points, b.water.unfit, b.water.source )
                                |> Expect.equal ( [ "Ponto 33" ], False, Just "IMA/SC" )

                        Nothing ->
                            Expect.fail "the fixture lost its beach"
            ]
        , describe "area switch"
            [ test "asks for the area's own file" <|
                \_ ->
                    Update.update (AreaPicked "rio") (page "") |> Tuple.second |> List.member (FetchWater "rio") |> Expect.equal True
            ]
        ]
