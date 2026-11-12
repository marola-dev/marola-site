module Difficulty exposing (Difficulty(..), band, decoder, parse)

{-| A trail's OSM `sac_scale`; a new OSM value shows as unrated, not as a crash.
-}

import Band exposing (Band)
import Dec
import Json.Decode as D exposing (Decoder)


type Difficulty
    = Hiking
    | MountainHiking
    | Unrated
    | Unknown String


parse : Maybe String -> Difficulty
parse value =
    case value of
        Just "hiking" ->
            Hiking

        Just "mountain_hiking" ->
            MountainHiking

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

        _ ->
            Band.Unscored


decoder : Decoder Difficulty
decoder =
    D.map parse (Dec.nullable D.string)
