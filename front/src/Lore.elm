module Lore exposing (Kind(..), Lore, decoder, labelKey)

{-| The day's sea-lore paragraph and the source it is quoted from. -}

import Dec
import Json.Decode as D exposing (Decoder)


type Kind
    = Secret
    | Creature
    | Unknown String


type alias Lore =
    { kind : Kind, text : String, source : String, lang : String }


parseKind : String -> Kind
parseKind value =
    case value of
        "secret" ->
            Secret

        "creature" ->
            Creature

        other ->
            Unknown other


{-| Only a creature has its own toggle label; every other kind reads as a fact.
-}
labelKey : Kind -> String
labelKey kind =
    case kind of
        Creature ->
            "lore.creature"

        _ ->
            "lore.fact"


decoder : Decoder Lore
decoder =
    D.map4 Lore
        (D.field "kind" (Dec.enum parseKind))
        (D.field "text" D.string)
        (D.field "source" D.string)
        (D.field "lang" D.string)
