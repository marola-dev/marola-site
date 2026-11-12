module DecoderTests exposing (suite)

import Area
import Board
import Expect
import Fixtures
import Json.Decode as D
import Msg exposing (Loaded(..))
import Support exposing (trailsSample)
import Test exposing (Test, describe, test)
import Trails
import Wire


withSchema : Int -> String
withSchema n =
    "{\"schema\":" ++ String.fromInt n ++ ",\"area\":\"x\"}"


suite : Test
suite =
    describe "decoders"
        [ test "the schema 2 fixture board reads with note codes" <|
            \_ ->
                case D.decodeString Wire.board Fixtures.board of
                    Ok (Read b) ->
                        Expect.all
                            [ \_ -> Expect.equal b.schema 2
                            , \_ -> Expect.notEqual b.beaches []
                            , \_ -> Expect.equal (List.any (\beach -> List.any (\h -> h.noteCodes /= []) beach.hours) b.beaches) True
                            ]
                            ()

                    other ->
                        Expect.fail (Debug.toString other |> String.left 300)
        , test "a schema 1 board reads, with no note codes" <|
            \_ ->
                case D.decodeString Wire.board Fixtures.boardSchema1 of
                    Ok (Read b) ->
                        Expect.equal ( b.schema, List.all (\beach -> List.all (\h -> h.noteCodes == []) beach.hours) b.beaches ) ( 1, True )

                    other ->
                        Expect.fail (Debug.toString other |> String.left 300)
        , test "a schema the page does not know is newer, not an error" <|
            \_ -> Expect.equal (D.decodeString Wire.board (withSchema 3)) (Ok (Newer 3))
        , test "a board with a known schema but a missing field fails" <|
            \_ -> Expect.err (D.decodeString Board.decoder (withSchema 2))
        , test "areas read as a list or under an areas key" <|
            \_ ->
                let
                    list =
                        D.decodeString Area.listDecoder Fixtures.areas |> Result.map (List.map .id)

                    wrapped =
                        D.decodeString Area.listDecoder ("{\"areas\":" ++ Fixtures.areas ++ "}") |> Result.map (List.map .id)
                in
                Expect.all
                    [ \_ -> Expect.equal (Result.map (List.member "floripa") list) (Ok True)
                    , \_ -> Expect.equal wrapped list
                    ]
                    ()
        , test "a trails file reads its routes in order and drops the lines it cannot draw" <|
            \_ ->
                Expect.equal
                    ( List.map .name (Trails.routes trailsSample)
                    , Trails.routeAt trailsSample 2 |> Maybe.map .name
                    , ( Trails.routeAt trailsSample -1, List.map (Trails.drawableLines >> List.length) (Trails.routes trailsSample) )
                    )
                    ( [ "Trilha A", "Trilha B", "Trilha C" ], Just "Trilha C", ( Nothing, [ 1, 0, 1 ] ) )
        ]
