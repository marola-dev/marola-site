module Level exposing (Level(..), decoder, parse, toString)

{-| The Low / Moderate / High likelihood of jellyfish and whales.
-}

import Dec
import Json.Decode exposing (Decoder)


type Level
    = Low
    | Moderate
    | High
    | Unknown String


parse : String -> Level
parse value =
    case value of
        "Low" ->
            Low

        "Moderate" ->
            Moderate

        "High" ->
            High

        other ->
            Unknown other


toString : Level -> String
toString level =
    case level of
        Low ->
            "Low"

        Moderate ->
            "Moderate"

        High ->
            "High"

        Unknown other ->
            other


decoder : Decoder Level
decoder =
    Dec.enum parse
