namespace Marola

open Thoth.Json.Core

/// The best hour of a beach.
type Best =
    { Hour: string
      Score: int
      Notes: string list
      NoteCodes: Note list }

/// One daylight hour the slider steps through.
type Hour =
    { H: string
      Score: int
      Notes: string list
      NoteCodes: Note list
      SeaTempC: float option
      WaveM: float option
      WindKmh: float option
      WindLevel: WindLevel option
      Jellyfish: Level
      Whales: Level }

/// What a beach shows at the hour on the slider: its best hour's score and notes, or an hour's. It
/// carries no sea numbers; `Beach.hourEntry` finds those.
type Shown =
    { H: string
      Score: int
      Notes: string list
      NoteCodes: Note list
      Best: bool }

module Hour =

    /// A schema-1 board has no note codes.
    let private noteCodes (get: Decode.IGetters) : Note list =
        get.Optional.Field "note_codes" (Decode.list Note.decoder)
        |> Option.defaultValue []

    let bestDecoder: Decoder<Best> =
        Decode.object (fun get ->
            { Hour = get.Required.Field "hour" Decode.string
              Score = get.Required.Field "score" Decoders.int
              Notes = get.Required.Field "notes" (Decode.list Decode.string)
              NoteCodes = noteCodes get })

    let decoder: Decoder<Hour> =
        Decode.object (fun get ->
            { H = get.Required.Field "h" Decode.string
              Score = get.Required.Field "score" Decoders.int
              Notes = get.Required.Field "notes" (Decode.list Decode.string)
              NoteCodes = noteCodes get
              SeaTempC = get.Required.Field "sea_temp_c" Decoders.nullableNumber
              WaveM = get.Required.Field "wave_m" Decoders.nullableNumber
              WindKmh = get.Required.Field "wind_kmh" Decoders.nullableNumber
              WindLevel = get.Optional.Field "wind_level" WindLevel.decoder
              Jellyfish = get.Required.Field "jellyfish" Level.decoder
              Whales = get.Required.Field "whales" Level.decoder })
