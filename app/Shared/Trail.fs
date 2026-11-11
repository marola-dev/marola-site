namespace Marola

open Thoth.Json.Core

/// The nearer beach or lake of a kind.
type NearAnchor = { Name: string; DistanceKm: float }

/// An OSM trail within 500 m of a beach or a named lake (MIP-0030).
type Trail =
    { Name: string
      LengthKm: float
      Difficulty: Difficulty
      Surface: string option
      Geometry: Point list
      NearBeach: NearAnchor option
      NearLake: NearAnchor option }

module Trail =

    /// A trail with fewer than two points cannot be drawn.
    let drawable (trail: Trail) : bool =
        match trail.Geometry with
        | _ :: _ :: _ -> true
        | _ -> false

    let private anchorDecoder: Decoder<NearAnchor> =
        Decode.object (fun get ->
            { Name = get.Required.Field "name" Decode.string
              DistanceKm = get.Required.Field "distance_km" Decoders.number })

    /// A `[lat, lon]` pair.
    let private latLonDecoder: Decoder<Point> =
        Decode.list Decoders.number
        |> Decode.andThen (fun pair ->
            match pair with
            | [ lat; lon ] -> Decode.succeed { Lat = lat; Lon = lon }
            | _ -> Decode.fail "Expecting a [lat, lon] pair")

    let decoder: Decoder<Trail> =
        Decode.object (fun get ->
            { Name = get.Required.Field "name" Decode.string
              LengthKm = get.Required.Field "length_km" Decoders.number
              Difficulty = get.Required.Field "difficulty" Difficulty.decoder
              Surface = get.Required.Field "surface" Decoders.nullableString
              Geometry = get.Required.Field "geometry" (Decode.list latLonDecoder)
              NearBeach = get.Required.Field "near_beach" (Decode.lossyOption anchorDecoder)
              NearLake = get.Required.Field "near_lake" (Decode.lossyOption anchorDecoder) })
