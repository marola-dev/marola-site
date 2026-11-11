namespace Marola

/// The colour ramp texture of the flow layer: evenly spaced hex stops as 256 RGBA texels.
module Ramp =

    let private white = (255, 255, 255)

    let private isHex (c: char) : bool =
        (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')

    let private hexValue (c: char) : int =
        if c >= '0' && c <= '9' then int c - int '0'
        elif c >= 'a' && c <= 'f' then int c - int 'a' + 10
        else int c - int 'A' + 10

    let private hexByte (high: char) (low: char) : int = hexValue high * 16 + hexValue low

    /// "#rrggbb" or "rrggbb"; anything else is white.
    let hexRgb (hex: string) : int * int * int =
        let trimmed = hex.Trim()

        let digits =
            if trimmed.StartsWith "#" then
                trimmed.Substring 1
            else
                trimmed

        if digits.Length = 6 && Seq.forall isHex digits then
            hexByte digits.[0] digits.[1], hexByte digits.[2] digits.[3], hexByte digits.[4] digits.[5]
        else
            white

    /// `Math.round(a * (1 - f) + b * f)`: halves round up.
    let private mix (a: int) (b: int) (f: float) : int =
        let value = float a * (1.0 - f) + float b * f
        int (System.Math.Floor(value + 0.5))

    let private texel (rgb: (int * int * int) array) (i: int) : int list =
        let last = rgb.Length - 1
        let t = float i / 255.0 * float last
        let k = min (last - 1) (int (System.Math.Floor t))
        let f = t - float k
        let r0, g0, b0 = rgb.[k]
        let r1, g1, b1 = rgb.[k + 1]
        [ mix r0 r1 f; mix g0 g1 f; mix b0 b1 f; 255 ]

    /// 1024 bytes, R G B A per texel. Needs two stops or more.
    let pixels (stops: string list) : int array option =
        let rgb = stops |> List.map hexRgb |> Array.ofList

        if rgb.Length < 2 then
            None
        else
            Some(Array.init 256 (texel rgb) |> Array.collect Array.ofList)
