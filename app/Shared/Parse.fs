namespace Marola

/// Strict number parsing that reads the same on .NET and under Fable. Neither runtime's own
/// parser is used bare: both accept white space, signs and forms the old page rejected.
module Parse =

    let private isDigit (c: char) = c >= '0' && c <= '9'

    let private digitsFrom (s: string) (start: int) : bool =
        start < s.Length && Seq.forall isDigit (s.Substring start)

    let private afterSign (s: string) : int =
        if s.Length > 0 && (s.[0] = '-' || s.[0] = '+') then
            1
        else
            0

    /// An integer: an optional sign, then digits only.
    let tryInt (s: string) : int option =
        if digitsFrom s (afterSign s) then
            match System.Int32.TryParse s with
            | true, v -> Some v
            | _ -> None
        else
            None

    /// A decimal number: an optional sign, digits, an optional fraction, an optional exponent.
    let tryFloat (s: string) : float option =
        let start = afterSign s
        let mantissaEnd = s.IndexOfAny [| 'e'; 'E' |]
        let mantissa = if mantissaEnd < 0 then s else s.Substring(0, mantissaEnd)

        let mantissaOk =
            match mantissa.IndexOf '.' with
            | -1 -> digitsFrom mantissa start
            | dot ->
                dot > start
                && digitsFrom (mantissa.Substring(start, dot - start)) 0
                && digitsFrom mantissa (dot + 1)

        let exponentOk =
            mantissaEnd < 0
            || (let e = s.Substring(mantissaEnd + 1)
                digitsFrom e (afterSign e))

        if mantissaOk && exponentOk then
#if FABLE_COMPILER
            match System.Double.TryParse s with
            | true, v -> Some v
            | _ -> None
#else
            match
                System.Double.TryParse(
                    s,
                    System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture
                )
            with
            | true, v -> Some v
            | _ -> None
#endif
        else
            None

    /// The shortest text that reads back as the same float, as JavaScript's `String(n)` does; the
    /// exponent form differs between runtimes ("1E-05" and "1e-7"), so callers read both.
    let shortest (n: float) : string =
#if FABLE_COMPILER
        string n
#else
        n.ToString("R", System.Globalization.CultureInfo.InvariantCulture)
#endif
