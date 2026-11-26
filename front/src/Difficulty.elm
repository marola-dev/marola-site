module Difficulty exposing (Difficulty(..), band, decoder, parse)

{-| A trail's OSM `sac_scale`, from T1 to T6; a new OSM value shows as unrated, not as a crash.
-}

import Band exposing (Band)
import Dec
import Json.Decode as D exposing (Decoder)


type Difficulty
    = Hiking
    | MountainHiking
    | DemandingMountainHiking
    | AlpineHiking
    | DemandingAlpineHiking
    | DifficultAlpineHiking
    | Unrated
    | Unknown String


parse : Maybe String -> Difficulty
parse value =
    case value of
        Just "hiking" ->
            Hiking

        Just "T1" ->
            Hiking

        Just "mountain_hiking" ->
            MountainHiking

        Just "T2" ->
            MountainHiking

        Just "demanding_mountain_hiking" ->
            DemandingMountainHiking

        Just "T3" ->
            DemandingMountainHiking

        Just "alpine_hiking" ->
            AlpineHiking

        Just "T4" ->
            AlpineHiking

        Just "demanding_alpine_hiking" ->
            DemandingAlpineHiking

        Just "T5" ->
            DemandingAlpineHiking

        Just "difficult_alpine_hiking" ->
            DifficultAlpineHiking

        Just "T6" ->
            DifficultAlpineHiking

        Just other ->
            Unknown other

        Nothing ->
            Unrated


band : Difficulty -> Band
band difficulty =
    case difficulty of
        Hiking ->
            Band.Good

        MountainHiking ->
            Band.Fair

        DemandingMountainHiking ->
            Band.Poor

        AlpineHiking ->
            Band.Avoid

        DemandingAlpineHiking ->
            Band.Avoid

        DifficultAlpineHiking ->
            Band.Avoid

        _ ->
            Band.Unscored


decoder : Decoder Difficulty
decoder =
    D.map parse (Dec.nullable D.string)
