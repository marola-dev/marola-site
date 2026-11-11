namespace Marola

open Thoth.Json.Core

/// The agency's verdict on a sampling point.
[<RequireQualifiedAccess>]
type Condition =
    | Proper
    | Improper
    | Unclassified
    | Unknown of string

type WaterPoint =
    { Point: string
      Location: string
      Lat: float
      Lon: float
      Condition: Condition
      SampledOn: string
      EnterococciPer100ml: int option
      Rain: string option }

/// A beach's water quality: the agency's verdict and its sampling points.
type Water =
    { Summary: string
      Unfit: bool
      Note: string option
      Source: string option
      Points: WaterPoint list }

module Condition =

    let parse (value: string) : Condition =
        match value with
        | "proper" -> Condition.Proper
        | "improper" -> Condition.Improper
        | "unknown" -> Condition.Unclassified
        | other -> Condition.Unknown other

    /// A sampling point's marker colour; anything but proper or improper is unscored.
    let band (condition: Condition) : Band =
        match condition with
        | Condition.Improper -> Band.Avoid
        | Condition.Proper -> Band.Good
        | _ -> Band.Unscored

    /// The agency's own words are Portuguese in every language; only the unclassified case goes
    /// through the catalog.
    let label (condition: Condition) (loc: Locale) : string =
        match condition with
        | Condition.Proper -> "PRÓPRIA"
        | Condition.Improper -> "IMPRÓPRIA"
        | Condition.Unclassified
        | Condition.Unknown _ -> I18n.t loc "water.unclassified" []

module Water =

    let private pointDecoder: Decoder<WaterPoint> =
        Decode.object (fun get ->
            { Point = get.Required.Field "point" Decode.string
              Location = get.Required.Field "location" Decode.string
              Lat = get.Required.Field "lat" Decoders.number
              Lon = get.Required.Field "lon" Decoders.number
              Condition = get.Required.Field "condition" (Decoders.enum Condition.parse)
              SampledOn = get.Required.Field "sampled_on" Decode.string
              EnterococciPer100ml = get.Required.Field "enterococci_per_100ml" Decoders.nullableInt
              Rain = get.Required.Field "rain" Decoders.nullableString })

    let decoder: Decoder<Water> =
        Decode.object (fun get ->
            { Summary = get.Required.Field "summary" Decode.string
              Unfit = get.Required.Field "unfit" Decode.bool
              Note = get.Required.Field "note" Decoders.nullableString
              Source = get.Required.Field "source" Decoders.nullableString
              Points = get.Required.Field "points" (Decode.list pointDecoder) })

    /// "no data" is the one summary the board writes in words rather than the agency's verdict.
    let hasNoData (water: Water) : bool = water.Summary = "no data"

    let summaryText (water: Water) (loc: Locale) : string =
        if hasNoData water then
            I18n.t loc "water.no_data" []
        else
            water.Summary

    let dotBand (water: Water) : Band =
        if water.Unfit then Band.Avoid
        elif hasNoData water then Band.Unscored
        else Band.Good

    let dotClass (water: Water) : string = "wdot " + Band.cssClass (dotBand water)
