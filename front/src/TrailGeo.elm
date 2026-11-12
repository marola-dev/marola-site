module TrailGeo exposing (collection, colour, tip)

{-| The trail routes as GeoJSON for the map's line layer. The id of a feature is the position of
its route, so a click on the map and a click in the panel name the same route.
-}

import Config
import Difficulty
import Fmt
import Geo exposing (Point)
import I18n exposing (Locale)
import Icons
import Json.Encode as E
import Trails exposing (Route, Trails)
import Tree exposing (Tree)


colour : Route -> String
colour route =
    Config.bandColour (Difficulty.band route.difficulty)


tip : Route -> Locale -> Tree
tip route loc =
    Tree.el "span" [] [ Icons.icon "footprints", Tree.text (" " ++ route.name ++ " · " ++ Fmt.value loc (Just route.lengthKm) " km" 1) ]


coordinates : List Point -> E.Value
coordinates line =
    E.list (\p -> E.list E.float [ p.lon, p.lat ]) line


feature : Int -> Route -> Locale -> Maybe E.Value
feature id route loc =
    case Trails.drawableLines route of
        [] ->
            Nothing

        lines ->
            Just
                (E.object
                    [ ( "type", E.string "Feature" )
                    , ( "properties"
                      , E.object
                            [ ( "id", E.int id )
                            , ( "color", E.string (colour route) )

                            -- MapLibre keeps a property that is not a number or text as text anyway; the map parses it back.
                            , ( "tip", E.string (E.encode 0 (Tree.toJson (tip route loc))) )
                            ]
                      )
                    , ( "geometry", E.object [ ( "type", E.string "MultiLineString" ), ( "coordinates", E.list coordinates lines ) ] )
                    ]
                )


{-| A route with no drawable line is left out, but keeps its id.
-}
collection : Maybe Trails -> Locale -> String
collection trails loc =
    let
        features =
            case trails of
                Nothing ->
                    []

                Just found ->
                    Trails.routes found |> List.indexedMap (\id route -> feature id route loc) |> List.filterMap identity
    in
    E.object [ ( "type", E.string "FeatureCollection" ), ( "features", E.list identity features ) ]
        |> E.encode 0
