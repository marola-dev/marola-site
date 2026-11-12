module Beach exposing (Beach, Facilities, Sea, Selection(..), Tide, Whales, decoder, hourEntry, shown)

import Dec exposing (andMap, required)
import Hour exposing (Best, Hour, Shown)
import Json.Decode as D exposing (Decoder)
import Level exposing (Level)
import Water exposing (Water)


type alias Tide =
    { time : String, m : Float, high : Bool }


{-| Conditions at the best hour.
-}
type alias Sea =
    { tempC : Maybe Float
    , waveM : Maybe Float
    , periodS : Maybe Float
    , waveDirDeg : Maybe Float
    , swellM : Maybe Float
    , swellPeriodS : Maybe Float
    , currentKmh : Maybe Float
    , windKmh : Maybe Float
    , windDirDeg : Maybe Float
    , airTempC : Maybe Float
    , uv : Maybe Float
    , rainPct : Maybe Float
    }


type alias Whales =
    { now : Level, peak : Maybe String, season : Bool }


{-| OSM amenity counts within 300 m. An absent key means no data, never zero.
-}
type alias Facilities =
    { parking : Maybe Int, toilets : Maybe Int, shower : Maybe Int, lifeguard : Maybe Int }


type alias Beach =
    { name : String
    , lat : Float
    , lon : Float
    , best : Best
    , hours : List Hour
    , water : Water
    , tides : List Tide
    , sea : Sea
    , jellyfish : Level
    , whales : Whales
    , facilities : Maybe Facilities
    }


{-| The slider's position: each beach at its own best hour, or one clock hour.
-}
type Selection
    = BestHour
    | At String


{-| `Nothing` is a beach dark at that hour.
-}
shown : Beach -> Selection -> Maybe Shown
shown beach selection =
    case selection of
        BestHour ->
            Just
                { h = beach.best.hour
                , score = beach.best.score
                , notes = beach.best.notes
                , noteCodes = beach.best.noteCodes
                , best = True
                }

        At h ->
            beach.hours
                |> List.filter (\x -> x.h == h)
                |> List.head
                |> Maybe.map (\x -> { h = x.h, score = x.score, notes = x.notes, noteCodes = x.noteCodes, best = False })


{-| The `hours` entry behind a shown hour, which has the numbers.
-}
hourEntry : Beach -> Maybe Shown -> Maybe Hour
hourEntry beach s =
    s |> Maybe.andThen (\x -> beach.hours |> List.filter (\e -> e.h == x.h) |> List.head)


tideDecoder : Decoder Tide
tideDecoder =
    D.map3 Tide (D.field "time" D.string) (D.field "m" Dec.number) (D.field "high" D.bool)


seaDecoder : Decoder Sea
seaDecoder =
    let
        n name =
            required name (Dec.nullable Dec.number)
    in
    D.succeed Sea
        |> n "temp_c"
        |> n "wave_m"
        |> n "period_s"
        |> n "wave_dir_deg"
        |> n "swell_m"
        |> n "swell_period_s"
        |> n "current_kmh"
        |> n "wind_kmh"
        |> n "wind_dir_deg"
        |> n "air_temp_c"
        |> n "uv"
        |> n "rain_pct"


whalesDecoder : Decoder Whales
whalesDecoder =
    D.map3 Whales (D.field "now" Level.decoder) (D.field "peak" (Dec.nullable D.string)) (D.field "season" D.bool)


facilitiesDecoder : Decoder Facilities
facilitiesDecoder =
    D.map4 Facilities
        (Dec.optional "parking" Dec.int)
        (Dec.optional "toilets" Dec.int)
        (Dec.optional "shower" Dec.int)
        (Dec.optional "lifeguard" Dec.int)


decoder : Decoder Beach
decoder =
    D.succeed Beach
        |> required "name" D.string
        |> required "lat" Dec.number
        |> required "lon" Dec.number
        |> required "best" Hour.bestDecoder
        |> required "hours" (D.list Hour.decoder)
        |> required "water" Water.decoder
        |> required "tides" (D.list tideDecoder)
        |> required "sea" seaDecoder
        |> required "jellyfish" Level.decoder
        |> required "whales" whalesDecoder
        |> andMap (Dec.optional "facilities" facilitiesDecoder)
