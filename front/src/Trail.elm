module Trail exposing (NearAnchor, Trail, decoder, drawable)

{-| An OSM trail within 500 m of a beach or a named lake (MIP-0030), as a board carries it. -}

import Dec exposing (required)
import Difficulty exposing (Difficulty)
import Geo exposing (Point)
import Json.Decode as D exposing (Decoder)


type alias NearAnchor =
    { name : String, distanceKm : Float }


type alias Trail =
    { name : String
    , lengthKm : Float
    , difficulty : Difficulty
    , surface : Maybe String
    , geometry : List Point
    , nearBeach : Maybe NearAnchor
    , nearLake : Maybe NearAnchor
    }


drawable : Trail -> Bool
drawable trail =
    List.length trail.geometry >= 2


anchorDecoder : Decoder NearAnchor
anchorDecoder =
    D.map2 NearAnchor (D.field "name" D.string) (D.field "distance_km" Dec.number)


decoder : Decoder Trail
decoder =
    D.succeed Trail
        |> required "name" D.string
        |> required "length_km" Dec.number
        |> required "difficulty" Difficulty.decoder
        |> required "surface" (Dec.nullable D.string)
        |> required "geometry" (D.list Geo.latLonDecoder)
        |> required "near_beach" (Dec.lossy anchorDecoder)
        |> required "near_lake" (Dec.lossy anchorDecoder)
