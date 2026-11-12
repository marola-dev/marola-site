module I18n exposing (Catalog, Locale, arg, lookup, messagesDecoder, numberArg, t, word)

{-| The message catalog and `t()`: a port of ui.js `lookup` and `t`. -}

import Dict exposing (Dict)
import Icu
import Json.Decode as D
import Language exposing (Language)


{-| The messages of each language, keyed by its tag.
-}
type alias Catalog =
    Dict String (Dict String String)


type alias Locale =
    { catalog : Catalog, language : Language }


messagesDecoder : D.Decoder (Dict String String)
messagesDecoder =
    D.dict D.string


lookup : Catalog -> Language -> String -> Maybe String
lookup catalog language key =
    Dict.get (Language.tag language) catalog |> Maybe.andThen (Dict.get key)


{-| The message in the language, else the source language's, else the key. A message that does
not parse also gives the key: the bundler rejects those at build time.
-}
t : Locale -> String -> List ( String, Icu.Arg ) -> String
t loc key args =
    let
        found =
            case lookup loc.catalog loc.language key of
                Just m ->
                    Just ( m, loc.language )

                Nothing ->
                    lookup loc.catalog Language.source key |> Maybe.map (\m -> ( m, Language.source ))
    in
    case found of
        Nothing ->
            key

        Just ( m, language ) ->
            case Icu.parse m of
                Ok nodes ->
                    Icu.format nodes args language Nothing

                Err _ ->
                    key


{-| A wire enum through the catalog (`wind.`, `lvl.`, `dir.`); a value with no key passes through.
-}
word : Locale -> String -> String -> String
word loc prefix value =
    let
        key =
            prefix ++ String.toLower value

        text =
            t loc key []
    in
    if text == key then
        value

    else
        text


arg : String -> String -> ( String, Icu.Arg )
arg name value =
    ( name, Icu.Text value )


numberArg : String -> Float -> ( String, Icu.Arg )
numberArg name value =
    ( name, Icu.Num value )
