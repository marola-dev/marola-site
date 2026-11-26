module DifficultyTests exposing (suite)

{-| The OSM `sac_scale` values, from T1 to T6, and the unknown one that must not crash.
-}

import Difficulty exposing (Difficulty(..))
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Difficulty"
        [ test "every sac_scale value has its T grade" <|
            \_ ->
                Expect.equal
                    (List.map Difficulty.parse
                        [ Just "hiking"
                        , Just "mountain_hiking"
                        , Just "demanding_mountain_hiking"
                        , Just "alpine_hiking"
                        , Just "demanding_alpine_hiking"
                        , Just "difficult_alpine_hiking"
                        ]
                    )
                    [ Hiking
                    , MountainHiking
                    , DemandingMountainHiking
                    , AlpineHiking
                    , DemandingAlpineHiking
                    , DifficultAlpineHiking
                    ]
        , test "the T1–T6 aliases read the same" <|
            \_ ->
                Expect.equal
                    (List.map Difficulty.parse [ Just "T1", Just "T2", Just "T3", Just "T4", Just "T5", Just "T6" ])
                    [ Hiking
                    , MountainHiking
                    , DemandingMountainHiking
                    , AlpineHiking
                    , DemandingAlpineHiking
                    , DifficultAlpineHiking
                    ]
        , test "no value is unrated; a new value is kept raw" <|
            \_ ->
                Expect.equal
                    ( Difficulty.parse Nothing, Difficulty.parse (Just "via_ferrata") )
                    ( Unrated, Unknown "via_ferrata" )
        ]
