// Decoder helpers shared by the board types. Thoth's own number and int decoders read a JSON
// string such as "48" as a number; a board that does that is wrong, so these read numbers only.
namespace Marola

open Thoth.Json.Core

module Decoders =

    /// A JSON number.
    let number: Decoder<float> =
        Decode.value
        |> Decode.andThen (fun json ->
            match json with
            | Json.Number n -> Decode.succeed n
            | _ -> Decode.fail "Expecting a number")

    /// A JSON number with no fractional part.
    let int: Decoder<int> =
        Decode.value
        |> Decode.andThen (fun json ->
            match json with
            | Json.Number n when n = System.Math.Floor n && abs n <= 2147483647.0 -> Decode.succeed (int n)
            | _ -> Decode.fail "Expecting an integer")

    /// A number or null: the board writes `null` for a missing measurement.
    let nullableNumber: Decoder<float option> = Decode.lossyOption number

    /// An integer or null.
    let nullableInt: Decoder<int option> = Decode.lossyOption int

    /// A string or null.
    let nullableString: Decoder<string option> = Decode.lossyOption Decode.string

    /// A closed set that must never crash the page: a value outside it becomes the caller's
    /// `Unknown` case instead of a decode error.
    let enum (parse: string -> 'a) : Decoder<'a> = Decode.string |> Decode.map parse
