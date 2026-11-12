module Board exposing (Board, Sources, decoder, hours, isPast, schemas)

{-| One area, one day: every nearby beach with every daylight hour scored (MIP-0005 section 5.2),
as `site/board.schema.json` says.
-}

import Beach exposing (Beach)
import Dec exposing (andMap, required)
import Json.Decode as D exposing (Decoder)
import Lore exposing (Lore)
import Trail exposing (Trail)


type alias Sources =
    { beaches : String, forecast : String, water : Maybe String }


type alias Board =
    { schema : Int
    , area : String
    , day : String
    , today : String
    , generatedAt : String
    , sources : Sources
    , lore : Maybe Lore
    , beaches : List Beach
    , trails : List Trail
    }


{-| The schemas this page reads; 2 adds note codes.
-}
schemas : List Int
schemas =
    [ 1, 2 ]


sourcesDecoder : Decoder Sources
sourcesDecoder =
    D.map3 Sources (D.field "beaches" D.string) (D.field "forecast" D.string) (D.field "water" (Dec.nullable D.string))


body : Int -> Decoder Board
body schema =
    D.succeed (Board schema)
        |> required "area" D.string
        |> required "day" D.string
        |> required "today" D.string
        |> required "generated_at" D.string
        |> required "sources" sourcesDecoder
        |> required "lore" (Dec.lossy Lore.decoder)
        |> required "beaches" (D.list Beach.decoder)
        |> andMap (Dec.optional "trails" (D.list Trail.decoder) |> D.map (Maybe.withDefault []))


decoder : Decoder Board
decoder =
    D.field "schema" Dec.int
        |> D.andThen
            (\schema ->
                if List.member schema schemas then
                    body schema

                else
                    D.fail ("Expecting schema " ++ (List.map String.fromInt schemas |> String.join " or ") ++ " but got " ++ String.fromInt schema)
            )


{-| The union of the beaches' hours, sorted by code unit: the slider's stops.
-}
hours : Board -> List String
hours board =
    board.beaches
        |> List.concatMap (\b -> List.map .h b.hours)
        |> List.foldl (\h acc -> if List.member h acc then acc else h :: acc) []
        |> List.sort


{-| Whether `h` has passed: only on the day the board was made, against the generation time.
-}
isPast : Board -> String -> Bool
isPast board h =
    board.day == board.today && h < String.slice 11 16 board.generatedAt
