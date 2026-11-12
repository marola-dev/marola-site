module Hour exposing (Best, Hour, Shown, bestDecoder, decoder)

import Dec exposing (andMap, required)
import Json.Decode as D exposing (Decoder)
import Level exposing (Level)
import Note exposing (Note)
import WindLevel exposing (WindLevel)


type alias Best =
    { hour : String, score : Int, notes : List String, noteCodes : List Note }


{-| One daylight hour the slider steps through.
-}
type alias Hour =
    { h : String
    , score : Int
    , notes : List String
    , noteCodes : List Note
    , seaTempC : Maybe Float
    , waveM : Maybe Float
    , windKmh : Maybe Float
    , windLevel : Maybe WindLevel
    , jellyfish : Level
    , whales : Level
    }


{-| What a beach shows at the slider's hour: its best hour's or one hour's score and notes.
-}
type alias Shown =
    { h : String, score : Int, notes : List String, noteCodes : List Note, best : Bool }


{-| A schema-1 board has no note codes.
-}
noteCodes : Decoder (List Note -> a) -> Decoder a
noteCodes =
    andMap (Dec.optional "note_codes" (D.list Note.decoder) |> D.map (Maybe.withDefault []))


bestDecoder : Decoder Best
bestDecoder =
    D.succeed Best
        |> required "hour" D.string
        |> required "score" Dec.int
        |> required "notes" (D.list D.string)
        |> noteCodes


decoder : Decoder Hour
decoder =
    D.succeed Hour
        |> required "h" D.string
        |> required "score" Dec.int
        |> required "notes" (D.list D.string)
        |> noteCodes
        |> required "sea_temp_c" (Dec.nullable Dec.number)
        |> required "wave_m" (Dec.nullable Dec.number)
        |> required "wind_kmh" (Dec.nullable Dec.number)
        |> andMap (Dec.optional "wind_level" WindLevel.decoder)
        |> required "jellyfish" Level.decoder
        |> required "whales" Level.decoder
