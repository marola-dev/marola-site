module WindLevel exposing (WindLevel(..), decoder, parse, toString)

{-| The wind band an hour carries. A board from before MIP-0054 has none. -}

import Dec
import Json.Decode exposing (Decoder)


type WindLevel
    = Calm
    | Breezy
    | Strong
    | Unknown String


parse : String -> WindLevel
parse value =
    case value of
        "calm" ->
            Calm

        "breezy" ->
            Breezy

        "strong" ->
            Strong

        other ->
            Unknown other


toString : WindLevel -> String
toString level =
    case level of
        Calm ->
            "calm"

        Breezy ->
            "breezy"

        Strong ->
            "strong"

        Unknown other ->
            other


decoder : Decoder WindLevel
decoder =
    Dec.enum parse
