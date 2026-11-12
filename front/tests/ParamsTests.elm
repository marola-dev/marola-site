module ParamsTests exposing (suite)

import Expect
import Params
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "params"
        [ test "parse reads pairs, with or without the question mark" <|
            \_ ->
                Expect.equal
                    (List.map Params.parse [ "?area=rio&day=2026-09-07", "area=rio", "", "?" ])
                    [ [ ( "area", "rio" ), ( "day", "2026-09-07" ) ], [ ( "area", "rio" ) ], [], [] ]
        , test "parse decodes percent escapes, plus and UTF-8, and keeps a stray percent" <|
            \_ ->
                Expect.equal
                    (List.map (\s -> Params.get (Params.parse s) "b") [ "?b=Praia%20Brava", "?b=a+b", "?b=%C3%A7", "?b=100%", "?b=%zz" ])
                    (List.map Just [ "Praia Brava", "a b", "ç", "100%", "%zz" ])
        , test "a key with no value reads as empty, and an absent key as none" <|
            \_ ->
                Expect.equal ( Params.parse "?flag", Params.get [] "x" ) ( [ ( "flag", "" ) ], Nothing )
        , test "set replaces in place or adds at the end; delete removes every copy" <|
            \_ ->
                let
                    q =
                        [ ( "a", "1" ), ( "b", "2" ) ]
                in
                Expect.equal
                    [ Params.set q "a" "9", Params.set q "c" "3", Params.delete [ ( "a", "1" ), ( "b", "2" ), ( "a", "3" ) ] "a" ]
                    [ [ ( "a", "9" ), ( "b", "2" ) ], [ ( "a", "1" ), ( "b", "2" ), ( "c", "3" ) ], [ ( "b", "2" ) ] ]
        , test "toString encodes what a URL cannot hold and round-trips through parse" <|
            \_ ->
                let
                    q =
                        [ ( "beach", "Praia da Joaquina" ), ( "x", "a&b=c#d" ), ( "n", "ção" ) ]

                    text =
                        Params.toString q
                in
                Expect.equal ( text, Params.parse text ) ( "beach=Praia%20da%20Joaquina&x=a%26b%3Dc%23d&n=%C3%A7%C3%A3o", q )
        ]
