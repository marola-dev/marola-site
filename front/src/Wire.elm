module Wire exposing (Request(..), board, days, decodeBody, env, requestUrl)

{-| What the page reads off the wire and off the browser, as values `Update` understands.
-}

import Board
import Dec
import Json.Decode as D exposing (Decoder)
import Language exposing (Language)
import Model exposing (DayEntry)
import Msg exposing (FetchError(..), Loaded(..))
import Params
import Update exposing (Env)


{-| A request the page made; its answer comes back tagged with it.
-}
type Request
    = Catalog Language
    | Areas
    | Latest String
    | BoardFile String String String
    | TrailsFile String


{-| Every URL starts with "./", so the page works from any path it is served under.
-}
requestUrl : Request -> String
requestUrl request =
    case request of
        Catalog language ->
            "./i18n/" ++ Language.tag language ++ ".json"

        Areas ->
            "./data/areas.json"

        Latest area ->
            "./data/" ++ area ++ "/latest.json"

        BoardFile area _ file ->
            "./data/" ++ area ++ "/" ++ file

        TrailsFile area ->
            "./data/trails/" ++ area ++ ".json"


{-| `status` is 0 for a body, -1 for a network failure, else the HTTP status.
-}
decodeBody : Decoder a -> Int -> String -> Result FetchError a
decodeBody decoder status body =
    if status == 0 then
        D.decodeString decoder body |> Result.mapError (D.errorToString >> BadData)

    else if status == -1 then
        Err NetworkError

    else
        Err (HttpError status)


{-| `data/<area>/latest.json`: the days that have a board, and each one's file.
-}
days : Decoder (List DayEntry)
days =
    D.field "days" (D.list (D.map2 DayEntry (D.field "day" D.string) (D.field "file" D.string)))


{-| A board this page reads, or the schema of one it does not: a newer board is news for the
visitor, not a decode error.
-}
board : Decoder Loaded
board =
    D.field "schema" Dec.int
        |> D.andThen
            (\schema ->
                if List.member schema Board.schemas then
                    D.map Read Board.decoder

                else
                    D.succeed (Newer schema)
            )


{-| The flags `ports.js` reads off the browser. Flags that do not decode give the page at its
root with no preference.
-}
env : D.Value -> Env
env flags =
    let
        decoder =
            D.map5 (\path search languages reduced stored -> { path = path, query = Params.parse search, languages = languages, reducedMotion = reduced, storedLanguage = stored })
                (D.field "path" D.string)
                (D.field "search" D.string)
                (D.field "languages" (D.list D.string))
                (D.field "reduced_motion" D.bool)
                (D.field "stored" D.string
                    |> D.map
                        (\s ->
                            if s == "" then
                                Nothing

                            else
                                Just s
                        )
                )
    in
    case D.decodeValue decoder flags of
        Ok found ->
            found

        Err _ ->
            { path = "/", query = [], languages = [], reducedMotion = False, storedLanguage = Nothing }
