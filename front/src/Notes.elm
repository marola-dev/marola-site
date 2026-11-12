module Notes exposing (ofShown, text)

{-| The reason lines of a score in the page's language: a port of app.js `noteText` and `notesOf`.
-}

import DateFmt
import Dict
import Fmt
import Hour exposing (Shown)
import I18n exposing (Locale)
import Icu
import Note exposing (Note, NoteArg(..))


toArg : Locale -> String -> NoteArg -> ( String, Icu.Arg )
toArg loc name a =
    case ( name, a ) of
        ( "wave_m", Number v ) ->
            I18n.arg name (Fmt.num loc v 1)

        ( "sea_temp_c", Number v ) ->
            I18n.arg name (Fmt.num loc v 1)

        ( "wind_kmh", Number v ) ->
            I18n.arg name (Fmt.num loc v 0)

        ( "rain_pct", Number v ) ->
            I18n.arg name (Fmt.num loc v 0)

        ( "sampled_on", Text day ) ->
            I18n.arg name (DateFmt.short day loc.language)

        ( "avoid", Places places ) ->
            I18n.arg name (String.join "; " places)

        ( _, Number v ) ->
            I18n.numberArg name v

        ( _, Text s ) ->
            I18n.arg name s

        ( _, Places places ) ->
            I18n.arg name (String.join "," places)

        -- A null: the only one the catalog reads is the bacteria count.
        ( "enterococci_per_100ml", Other ) ->
            I18n.arg name "na"

        ( _, Other ) ->
            I18n.arg name "null"


text : Note -> Maybe String -> Locale -> String
text note english loc =
    let
        given =
            Dict.toList note.args |> List.map (\( n, a ) -> toArg loc n a)

        args =
            if List.any (\( k, _ ) -> k == "enterococci_per_100ml") given then
                given

            else
                I18n.arg "enterococci_per_100ml" "na" :: given

        key =
            "note." ++ note.code

        out =
            I18n.t loc key args
    in
    if out /= key then
        out

    else
        Maybe.withDefault note.code english


{-| A board with no note codes (schema 1) has only the English lines.
-}
ofShown : Shown -> Locale -> List String
ofShown shown loc =
    case shown.noteCodes of
        [] ->
            shown.notes

        codes ->
            List.indexedMap (\i code -> text code (List.drop i shown.notes |> List.head) loc) codes
