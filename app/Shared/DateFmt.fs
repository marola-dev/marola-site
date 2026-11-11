namespace Marola

/// A calendar day as the page prints it: `Intl.DateTimeFormat(locale, {day: 'numeric', month:
/// 'short'})` on a UTC date. Written out as tables so .NET and JavaScript print the same text.
module DateFmt =

    let private ptMonths =
        [| "jan."
           "fev."
           "mar."
           "abr."
           "mai."
           "jun."
           "jul."
           "ago."
           "set."
           "out."
           "nov."
           "dez." |]

    let private enMonths =
        [| "Jan"
           "Feb"
           "Mar"
           "Apr"
           "May"
           "Jun"
           "Jul"
           "Aug"
           "Sep"
           "Oct"
           "Nov"
           "Dec" |]

    /// "2026-11-07" is "7 de nov." in pt-BR and "Nov 7" in English. Text that is not an ISO day
    /// comes back as it is.
    let short (iso: string) (language: Language) : string =
        match iso.Split '-' with
        | [| _; month; day |] ->
            match Parse.tryInt month, Parse.tryInt (day.Substring(0, min 2 day.Length)) with
            | Some m, Some d when m >= 1 && m <= 12 ->
                match language with
                | Language.PtBr -> string d + " de " + ptMonths.[m - 1]
                | Language.En -> enMonths.[m - 1] + " " + string d
            | _ -> iso
        | _ -> iso

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
    let private toDays (year: int) (month: int) (day: int) : int =
        let y = if month <= 2 then year - 1 else year
        let era = y / 400
        let yoe = y - era * 400
        let shifted = if month > 2 then month - 3 else month + 9
        let doy = (153 * shifted + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        era * 146097 + doe - 719468

    let private pad (n: int) (width: int) : string = (string n).PadLeft(width, '0')

    let private fromDays (days: int) : string =
        let z = days + 719468
        let era = z / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = if mp < 10 then mp + 3 else mp - 9
        let year = if month <= 2 then yoe + era * 400 + 1 else yoe + era * 400
        pad year 4 + "-" + pad month 2 + "-" + pad day 2

    /// The ISO day `days` before `iso`, by the proleptic Gregorian calendar. A text that is not an
    /// ISO day comes back as it is. The satellite layers ask for the imagery of a day or two
    /// before the board's.
    let minusDays (iso: string) (days: int) : string =
        match iso.Split '-' with
        | [| y; m; d |] ->
            match Parse.tryInt y, Parse.tryInt m, Parse.tryInt d with
            | Some year, Some month, Some day when year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= 31 ->
                fromDays (toDays year month day - days)
            | _ -> iso
        | _ -> iso
