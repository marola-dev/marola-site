namespace Marola

/// How app.js writes a number with its unit: `num`, `value`, `waves` and `signed`.
module Fmt =

    /// A number with exactly `digits` fraction digits, in the page's language.
    let num (loc: Locale) (n: float) (digits: int) : string =
        NumFmt.fixedDigits n loc.Language digits digits

    /// app.js `.replace(' ', '\u00a0')` changes the first space only.
    let private firstSpaceToNbsp (unit: string) : string =
        match unit.IndexOf ' ' with
        | -1 -> unit
        | i -> unit.Substring(0, i) + "\u00A0" + unit.Substring(i + 1)

    /// A value and its unit; a no-break space keeps "6 s" together when a tooltip cell wraps. No
    /// value reads "n/a".
    let value (loc: Locale) (n: float option) (unit: string) (digits: int) : string =
        match n with
        | None -> I18n.t loc "common.na" []
        | Some n -> num loc n digits + firstSpaceToNbsp unit

    /// The waves cell: height, and the period when there is one.
    let waves (loc: Locale) (waveM: float option) (periodS: float option) : string =
        I18n.t
            loc
            "cell.waves"
            [ I18n.arg "m" (value loc waveM " m" 1)
              I18n.arg "every" (if periodS.IsNone then "no" else "yes")
              I18n.arg "s" (value loc periodS " s" 0) ]

    /// A number with a sign unless it prints as zero: `Intl.NumberFormat` with `signDisplay:
    /// 'exceptZero'`. The tide's height above the mean level.
    let signed (loc: Locale) (n: float) (digits: int) : string =
        let body = num loc (abs n) digits
        let isZero = body = num loc 0.0 digits

        if isZero then body
        elif n < 0.0 then "-" + body
        else "+" + body
