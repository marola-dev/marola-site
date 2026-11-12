module Trails exposing (Group, Route, Trails, decoder, drawableLines, fromBoard, isEmpty, routeAt, routes, wayUrl)

{-| Hiking routes of an area (OpenStreetMap, ODbL 1.0) grouped by bairro, from
`data/trails/<area>.json`; a board's own `trails` (MIP-0030) stand in when an area has no file.
-}

import Dec exposing (andMap, required)
import Difficulty exposing (Difficulty)
import Geo exposing (Point)
import Json.Decode as D exposing (Decoder)
import Trail exposing (Trail)


type alias Route =
    { name : String
    , lengthKm : Float
    , difficulty : Difficulty
    , surface : Maybe String
    , osmWays : List Int
    , lines : List (List Point)
    }


{-| A board's trails belong to no bairro.
-}
type alias Group =
    { bairro : Maybe String, routes : List Route }


type alias Trails =
    { area : String
    , ibgeMunicipality : Maybe String
    , source : String
    , licence : Maybe String
    , osmBase : Maybe String
    , note : Maybe String
    , groups : List Group
    }


schema : Int
schema =
    1


{-| The position of a route in this list is its id on the map and in the panel.
-}
routes : Trails -> List Route
routes trails =
    List.concatMap .routes trails.groups


routeAt : Trails -> Int -> Maybe Route
routeAt trails id =
    if id < 0 then
        Nothing

    else
        routes trails |> List.drop id |> List.head


isEmpty : Trails -> Bool
isEmpty trails =
    List.isEmpty (routes trails)


drawableLines : Route -> List (List Point)
drawableLines route =
    List.filter (\line -> List.length line >= 2) route.lines


wayUrl : Int -> String
wayUrl id =
    "https://www.openstreetmap.org/way/" ++ String.fromInt id


fromBoard : String -> List Trail -> Trails
fromBoard area trails =
    let
        found =
            trails
                |> List.filter Trail.drawable
                |> List.map
                    (\t ->
                        { name = t.name
                        , lengthKm = t.lengthKm
                        , difficulty = t.difficulty
                        , surface = t.surface
                        , osmWays = []
                        , lines = [ t.geometry ]
                        }
                    )
    in
    { area = area
    , ibgeMunicipality = Nothing
    , source = "OpenStreetMap contributors"
    , licence = Just "ODbL-1.0"
    , osmBase = Nothing
    , note = Nothing
    , groups =
        if List.isEmpty found then
            []

        else
            [ { bairro = Nothing, routes = found } ]
    }


routeDecoder : Decoder Route
routeDecoder =
    D.succeed Route
        |> required "name" D.string
        |> required "length_km" Dec.number
        |> required "difficulty" Difficulty.decoder
        |> required "surface" (Dec.nullable D.string)
        |> required "osm_ways" (D.list Dec.int)
        |> required "lines" (D.list (D.list Geo.latLonDecoder))


groupDecoder : Decoder Group
groupDecoder =
    D.map2 Group (D.field "bairro" (D.map Just D.string)) (D.field "trails" (D.list routeDecoder))


body : Decoder Trails
body =
    D.succeed Trails
        |> required "area" D.string
        |> required "ibge_municipality" (D.map Just D.string)
        |> required "source" D.string
        |> required "licence" (D.map Just D.string)
        |> required "osm_base" (D.map Just D.string)
        |> andMap (Dec.optional "note" D.string)
        |> required "bairros" (D.list groupDecoder)


decoder : Decoder Trails
decoder =
    D.field "schema" Dec.int
        |> D.andThen
            (\found ->
                if found == schema then
                    body

                else
                    D.fail ("Expecting schema " ++ String.fromInt schema ++ " but got " ++ String.fromInt found)
            )
