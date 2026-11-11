namespace Marola

/// Number formatting for pt-BR and en, without Intl, so .NET and JavaScript print the same text.
/// It rounds the shortest decimal text of the float, half away from zero, as ECMA-402 does, so
/// 1.005 prints 1.01.
module NumFmt =

    let private separators (language: Language) : string * string =
        match language with
        | Language.PtBr -> ".", ","
        | Language.En -> ",", "."

    /// The significant digits and the count of digits before the decimal point (zero or negative
    /// for 0.00ddd): the value is 0.DIGITS * 10^point.
    let private decimalDigits (n: float) : int list * int =
        let text = Parse.shortest n

        let mantissa, exponent =
            match text.Split [| 'e'; 'E' |] with
            | [| m; e |] -> m, Parse.tryInt e |> Option.defaultValue 0
            | _ -> text, 0

        let whole, fraction =
            match mantissa.Split '.' with
            | [| w; f |] -> w, f
            | _ -> mantissa, ""

        let all = (whole + fraction) |> Seq.map (fun c -> int c - int '0') |> List.ofSeq
        let point = whole.Length + exponent

        let rec strip (digits: int list) (point: int) =
            match digits with
            | 0 :: rest -> strip rest (point - 1)
            | _ -> if List.forall ((=) 0) digits then [], 0 else digits, point

        strip all point

    /// Add one unit in the last kept place; a carry out of the first digit adds a digit.
    let private increment (kept: int list) (point: int) : int list * int =
        let folder digit (done', carry) =
            match carry, digit with
            | true, 9 -> 0 :: done', true
            | true, d -> (d + 1) :: done', false
            | false, d -> d :: done', false

        match List.foldBack folder kept ([], true) with
        | done', true -> 1 :: done', point + 1
        | done', false -> done', point

    /// Keep `point + max` digits; a dropped digit of 5 or more rounds up.
    let private round (digits: int list) (point: int) (max: int) : int list * int =
        let keep = point + max

        if keep < 0 then
            [], 0
        elif keep >= List.length digits then
            digits, point
        else
            let kept = List.take keep digits
            let next = List.item keep digits
            if next >= 5 then increment kept point else kept, point

    let private wholePart (digits: int list) (point: int) : string =
        if point <= 0 then
            "0"
        else
            List.append digits (List.replicate point 0)
            |> List.take point
            |> List.map string
            |> String.concat ""

    let rec private trimTrailingZeros (digits: int list) (min: int) : int list =
        if List.length digits > min && List.last digits = 0 then
            trimTrailingZeros (List.take (List.length digits - 1) digits) min
        else
            digits

    let private fractionPart (digits: int list) (point: int) (min: int) : string =
        let leading = if point < 0 then List.replicate (-point) 0 else []

        let afterPoint =
            if point < 0 then
                digits
            else
                List.skip (Operators.min point (List.length digits)) digits

        let trimmed = trimTrailingZeros (List.append leading afterPoint) min

        let padded =
            List.append trimmed (List.replicate (Operators.max 0 (min - List.length trimmed)) 0)

        padded |> List.map string |> String.concat ""

    /// The digits of `whole` in groups of three, from the right.
    let private grouped (whole: string) (separator: string) : string =
        let first =
            match whole.Length % 3 with
            | 0 -> 3
            | n -> n

        let rec loop (rest: string) (take: int) (acc: string list) =
            if rest = "" then
                List.rev acc
            else
                let chunk = rest.Substring(0, Operators.min take rest.Length)
                loop (rest.Substring chunk.Length) 3 (chunk :: acc)

        loop whole first [] |> String.concat separator

    /// Like Intl's minimumFractionDigits and maximumFractionDigits.
    let fixedDigits (n: float) (language: Language) (min: int) (max: int) : string =
        let digits, point = decimalDigits (abs n)
        let digits, point = round digits point max
        let whole = wholePart digits point
        let fraction = fractionPart digits point min
        let group, decimalMark = separators language

        let body =
            if fraction = "" then
                grouped whole group
            else
                grouped whole group + decimalMark + fraction

        if n < 0.0 then "-" + body else body

    /// What `new Intl.NumberFormat(locale).format(n)` prints: up to 3 fraction digits.
    let format (n: float) (language: Language) : string = fixedDigits n language 0 3
