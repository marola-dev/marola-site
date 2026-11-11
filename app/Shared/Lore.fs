namespace Marola

open Thoth.Json.Core

/// The day's sea-lore paragraph and the source it is quoted from.
[<RequireQualifiedAccess>]
type LoreKind =
    | Secret
    | Creature
    | Unknown of string

type Lore =
    { Kind: LoreKind
      Text: string
      Source: string
      Lang: string }

module Lore =

    let parseKind (value: string) : LoreKind =
        match value with
        | "secret" -> LoreKind.Secret
        | "creature" -> LoreKind.Creature
        | other -> LoreKind.Unknown other

    /// The footer's toggle label: only a creature has its own; every other kind reads as a fact.
    let labelKey (kind: LoreKind) : string =
        match kind with
        | LoreKind.Creature -> "lore.creature"
        | _ -> "lore.fact"

    let decoder: Decoder<Lore> =
        Decode.object (fun get ->
            { Kind = get.Required.Field "kind" (Decoders.enum parseKind)
              Text = get.Required.Field "text" Decode.string
              Source = get.Required.Field "source" Decode.string
              Lang = get.Required.Field "lang" Decode.string })
