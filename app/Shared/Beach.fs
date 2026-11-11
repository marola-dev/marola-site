namespace Marola

open Thoth.Json.Core

type Tide = { Time: string; M: float; High: bool }

/// Conditions at the best hour.
type Sea =
    { TempC: float option
      WaveM: float option
      PeriodS: float option
      WaveDirDeg: float option
      SwellM: float option
      SwellPeriodS: float option
      CurrentKmh: float option
      WindKmh: float option
      WindDirDeg: float option
      AirTempC: float option
      Uv: float option
      RainPct: float option }

type Whales =
    { Now: Level
      Peak: string option
      Season: bool }

/// OSM amenity counts within 300 m. An absent key means no data, never zero.
type Facilities =
    { Parking: int option
      Toilets: int option
      Shower: int option
      Lifeguard: int option }

/// A beach: where it is, how it scores hour by hour, its water, sea and facilities.
type Beach =
    { Name: string
      Lat: float
      Lon: float
      Best: Best
      Hours: Hour list
      Water: Water
      Tides: Tide list
      Sea: Sea
      Jellyfish: Level
      Whales: Whales
      Facilities: Facilities option }

/// The slider's position: each beach at its own best hour, or one clock hour.
[<RequireQualifiedAccess>]
type Selection =
    | BestHour
    | At of string

module Beach =

    /// The shape a beach shows for the slider position. `None` means the beach is dark at that hour.
    let shown (beach: Beach) (selection: Selection) : Shown option =
        match selection with
        | Selection.BestHour ->
            Some
                { H = beach.Best.Hour
                  Score = beach.Best.Score
                  Notes = beach.Best.Notes
                  NoteCodes = beach.Best.NoteCodes
                  Best = true }
        | Selection.At h ->
            beach.Hours
            |> List.tryFind (fun (x: Hour) -> x.H = h)
            |> Option.map (fun x ->
                { H = x.H
                  Score = x.Score
                  Notes = x.Notes
                  NoteCodes = x.NoteCodes
                  Best = false })

    /// The `Hours` entry behind a shown hour, which has the numbers.
    let hourEntry (beach: Beach) (shown: Shown option) : Hour option =
        shown
        |> Option.bind (fun s -> beach.Hours |> List.tryFind (fun (x: Hour) -> x.H = s.H))

    let private tideDecoder: Decoder<Tide> =
        Decode.object (fun get ->
            { Time = get.Required.Field "time" Decode.string
              M = get.Required.Field "m" Decoders.number
              High = get.Required.Field "high" Decode.bool })

    let private seaDecoder: Decoder<Sea> =
        let n = Decoders.nullableNumber

        Decode.object (fun get ->
            { TempC = get.Required.Field "temp_c" n
              WaveM = get.Required.Field "wave_m" n
              PeriodS = get.Required.Field "period_s" n
              WaveDirDeg = get.Required.Field "wave_dir_deg" n
              SwellM = get.Required.Field "swell_m" n
              SwellPeriodS = get.Required.Field "swell_period_s" n
              CurrentKmh = get.Required.Field "current_kmh" n
              WindKmh = get.Required.Field "wind_kmh" n
              WindDirDeg = get.Required.Field "wind_dir_deg" n
              AirTempC = get.Required.Field "air_temp_c" n
              Uv = get.Required.Field "uv" n
              RainPct = get.Required.Field "rain_pct" n })

    let private whalesDecoder: Decoder<Whales> =
        Decode.object (fun get ->
            { Now = get.Required.Field "now" Level.decoder
              Peak = get.Required.Field "peak" Decoders.nullableString
              Season = get.Required.Field "season" Decode.bool })

    let private facilitiesDecoder: Decoder<Facilities> =
        Decode.object (fun get ->
            let count key = get.Optional.Field key Decoders.int

            { Parking = count "parking"
              Toilets = count "toilets"
              Shower = count "shower"
              Lifeguard = count "lifeguard" })

    let decoder: Decoder<Beach> =
        Decode.object (fun get ->
            { Name = get.Required.Field "name" Decode.string
              Lat = get.Required.Field "lat" Decoders.number
              Lon = get.Required.Field "lon" Decoders.number
              Best = get.Required.Field "best" Hour.bestDecoder
              Hours = get.Required.Field "hours" (Decode.list Hour.decoder)
              Water = get.Required.Field "water" Water.decoder
              Tides = get.Required.Field "tides" (Decode.list tideDecoder)
              Sea = get.Required.Field "sea" seaDecoder
              Jellyfish = get.Required.Field "jellyfish" Level.decoder
              Whales = get.Required.Field "whales" whalesDecoder
              Facilities = get.Optional.Field "facilities" facilitiesDecoder })
