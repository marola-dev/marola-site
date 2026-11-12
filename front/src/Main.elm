port module Main exposing (main)

{-| The page's entry point: `Update` runs the page, and this module carries out the effects it
asks for through two ports. `ports.js` holds MapLibre, WebGL, fetch and the browser's storage,
history and audio.
-}

import Area
import Browser
import Config
import Effect exposing (Effect(..))
import I18n
import Json.Decode as D
import Json.Encode as E
import Language
import MapJson
import Model exposing (Model)
import Msg exposing (Msg(..))
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


fetch : Request -> Cmd msg
fetch request =
    send "fetch" [ ( "url", E.string (Wire.requestUrl request) ), ( "req", Wire.encodeRequest request ) ]


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
            send "focus" (text "id" id)


{-| What `ports.js` sends back: an answer to a request, a map event, or a position.
-}
incoming : D.Value -> Msg
incoming value =
    D.decodeValue (D.field "kind" D.string |> D.andThen incomingOf) value
        |> Result.withDefault Ignored


incomingOf : String -> D.Decoder Msg
incomingOf kind =
    case kind of
        "fetched" ->
            D.map3 answered (D.field "req" Wire.requestDecoder) (D.field "status" D.int) (D.field "body" (D.oneOf [ D.string, D.null "" ]))

        "map" ->
            D.map2 MapEvent (D.field "event" D.string) (D.field "arg" D.string)

        "located" ->
            D.map2 (\lat lon -> Located (Ok { lat = lat, lon = lon })) (D.field "lat" D.float) (D.field "lon" D.float)

        "locateFailed" ->
            D.map (Located << Err) (D.field "why" D.string)

        _ ->
            D.fail kind


answered : Request -> Int -> String -> Msg
answered request status body =
    let
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
