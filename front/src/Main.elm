port module Main exposing (main)

{-| The page's entry point: `Update` runs the page, and this module carries out the effects it
asks for. Requests and focus are Elm's own (elm/http, Browser.Dom); the rest goes through two
ports, because `ports.js` holds what Elm has no binding for: MapLibre, WebGL, geolocation, the
browser's storage and history, the document's language, and alerts (ADR 0007).
-}

import Area
import Browser
import Browser.Dom
import Config
import Effect exposing (Effect(..))
import Http
import I18n
import Json.Decode as D
import Json.Encode as E
import Language
import MapJson
import Model exposing (Model)
import Msg exposing (Msg(..))
import Task
import Trails
import Update
import View.Page
import Wire exposing (Request(..))


port toJs : E.Value -> Cmd msg


port fromJs : (D.Value -> msg) -> Sub msg


main : Program D.Value Model Msg
main =
    Browser.element
        { init = \flags -> Update.init (Wire.env flags) |> withEffects
        , update = \msg model -> Update.update msg model |> withEffects
        , view = View.Page.view
        , subscriptions = \_ -> fromJs incoming
        }


withEffects : ( Model, List Effect ) -> ( Model, Cmd Msg )
withEffects ( model, effects ) =
    ( model, Cmd.batch (List.map run effects) )


send : String -> List ( String, E.Value ) -> Cmd msg
send kind fields =
    toJs (E.object (( "kind", E.string kind ) :: fields))


{-| A GET whose answer reaches `answered` as the ports once sent it: status 0 with the body, -1 for
a network failure, else the HTTP status.
-}
fetch : Request -> Cmd Msg
fetch request =
    Http.get
        { url = Wire.requestUrl request
        , expect = Http.expectStringResponse (answered request) (\response -> Ok (statusOf response))
        }


statusOf : Http.Response String -> ( Int, String )
statusOf response =
    case response of
        Http.GoodStatus_ _ body ->
            ( 0, body )

        Http.BadStatus_ metadata _ ->
            ( metadata.statusCode, "" )

        Http.BadUrl_ _ ->
            ( -1, "" )

        Http.Timeout_ ->
            ( -1, "" )

        Http.NetworkError_ ->
            ( -1, "" )


text : String -> String -> List ( String, E.Value )
text name value =
    [ ( name, E.string value ) ]


run : Effect -> Cmd Msg
run effect =
    case effect of
        FetchCatalog language ->
            fetch (Catalog language)

        FetchAreas ->
            fetch Areas

        FetchLatest area ->
            fetch (Latest area)

        FetchBoard area day file ->
            fetch (BoardFile area day file)

        FetchTrails area ->
            fetch (TrailsFile area)

        ReplaceUrl path query ->
            send "replaceUrl" (text "path" path ++ text "query" query)

        SetDocument language title ->
            send "setDocument" (text "language" language ++ text "title" title)

        StoreLanguage language ->
            send "storeLanguage" (text "tag" (Language.tag language))

        InitMap lon lat ->
            send "initMap" (text "json" (MapJson.mapConfig lon lat))

        SyncMap json ->
            send "syncMap" (text "json" json)

        SetTrails json ->
            send "setTrails" (text "json" json)

        SetFlow json ->
            send "setFlow" (text "json" json)

        MoveCamera view ->
            send "camera" (text "json" (MapJson.cameraJson view))

        Locate ->
            send "locate" []

        Alert message ->
            send "alert" (text "text" message)

        Focus id ->
            Task.attempt (\_ -> Ignored) (Browser.Dom.focus id)


{-| What `ports.js` sends back: a map event or a position.
-}
incoming : D.Value -> Msg
incoming value =
    D.decodeValue (D.field "kind" D.string |> D.andThen incomingOf) value
        |> Result.withDefault Ignored


incomingOf : String -> D.Decoder Msg
incomingOf kind =
    case kind of
        "map" ->
            D.map2 MapEvent (D.field "event" D.string) (D.field "arg" D.string)

        "located" ->
            D.map2 (\lat lon -> Located (Ok { lat = lat, lon = lon })) (D.field "lat" D.float) (D.field "lon" D.float)

        "locateFailed" ->
            D.map (Located << Err) (D.field "why" D.string)

        _ ->
            D.fail kind


answered : Request -> Result Never ( Int, String ) -> Msg
answered request result =
    let
        ( status, body ) =
            case result of
                Ok answer ->
                    answer

                Err impossible ->
                    never impossible

        decode decoder =
            Wire.decodeBody decoder status body
    in
    case request of
        Catalog language ->
            CatalogLoaded language (decode I18n.messagesDecoder)

        Areas ->
            AreasLoaded (decode Area.listDecoder)

        Latest area ->
            LatestLoaded area (decode Wire.days)

        BoardFile area day file ->
            BoardLoaded area day file (decode Wire.board)

        TrailsFile area ->
            TrailsFileLoaded area (decode Trails.decoder)
