module WaterTests exposing (suite)

{-| The board's water summary, in the app's English grammar, said in each language.
-}

import Expect
import Language exposing (Language(..))
import Support exposing (locale)
import Test exposing (Test, describe, test)
import Water exposing (Condition(..), Summary(..))


water : String -> Water.Water
water summary =
    { summary = summary, unfit = False, note = Nothing, source = Nothing, points = [] }


says : Language -> String -> String -> Test
says language summary want =
    test (Language.tag language ++ ": " ++ summary) <|
        \_ -> Water.summaryText (water summary) (locale language) |> Expect.equal want


suite : Test
suite =
    describe "Water"
        [ describe "parseSummary"
            [ test "mixed" <|
                \_ ->
                    Water.parseSummary "5/7 PRÓPRIA — avoid Ponto 69, Ponto 04 (11 Nov)"
                        |> Expect.equal (Mixed { proper = "5", total = "7", avoid = "Ponto 69, Ponto 04", when = "11 Nov" })
            , test "fit with unknowns" <|
                \_ ->
                    Water.parseSummary "PRÓPRIA (2/3 pts, 1 unknown, 9 Nov)"
                        |> Expect.equal (Fit { proper = "2", total = "3", unknown = Just "1", when = "9 Nov" })
            , test "an unknown shape stays as it came" <|
                \_ -> Water.parseSummary "0/5 IMPRÓPRIA" |> Expect.equal (Raw "0/5 IMPRÓPRIA")
            ]
        , describe "summaryText"
            [ says En "no data" "no data"
            , says PtBr "no data" "sem dados"
            , says En "PRÓPRIA (2/2 pts, 9 Nov)" "fit (2/2 points, Nov 9)"
            , says PtBr "PRÓPRIA (2/2 pts, 9 Nov)" "PRÓPRIA (2/2 pontos, 9 de nov.)"
            , says En "PRÓPRIA (2/3 pts, 1 unknown, 9 Nov)" "fit (2/3 points, 1 unclassified, Nov 9)"
            , says En "IMPRÓPRIA (1/1 pts, 10 Nov)" "unfit (1/1 points, Nov 10)"
            , says PtBr "IMPRÓPRIA (1/1 pts, 10 Nov)" "IMPRÓPRIA (1/1 pontos, 10 de nov.)"
            , says En "5/6 PRÓPRIA — avoid Ponto 54 (11 Nov)" "5/6 points fit; avoid Ponto 54 (Nov 11)"
            , says PtBr "5/6 PRÓPRIA — avoid Ponto 54 (11 Nov)" "5/6 pontos PRÓPRIA; evite Ponto 54 (11 de nov.)"
            , says En "no verdict (2 pts unknown, 9 Nov)" "no verdict (2 points unclassified, Nov 9)"
            , says PtBr "stale (25 Aug)" "laudo antigo (25 de ago.)"
            , says En "0/5 IMPRÓPRIA" "0/5 IMPRÓPRIA"
            ]
        , describe "conditionLabel"
            [ test "en" <|
                \_ ->
                    List.map (\c -> Water.conditionLabel c (locale En)) [ Proper, Improper, Unclassified ]
                        |> Expect.equal [ "fit", "unfit", "unclassified" ]
            , test "pt-BR keeps the agency's words" <|
                \_ ->
                    List.map (\c -> Water.conditionLabel c (locale PtBr)) [ Proper, Improper, Unclassified ]
                        |> Expect.equal [ "PRÓPRIA", "IMPRÓPRIA", "sem classificação" ]
            ]
        ]
