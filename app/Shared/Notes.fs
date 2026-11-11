namespace Marola

/// The reason lines of a score, in the page's language. A port of app.js `noteText` and
/// `notesOf`: a code with a catalog key reads in the language; a code this page has no key for
/// keeps the board's English.
module Notes =

    /// The numbers the English lines rounded; a day and a list of places as the page prints them.
    let private toArg (loc: Locale) (name: string) (arg: NoteArg) : string * IcuArg =
        match name, arg with
        | "wave_m", NoteArg.Number v
        | "sea_temp_c", NoteArg.Number v -> I18n.arg name (Fmt.num loc v 1)
        | "wind_kmh", NoteArg.Number v
        | "rain_pct", NoteArg.Number v -> I18n.arg name (Fmt.num loc v 0)
        | "sampled_on", NoteArg.Text day -> I18n.arg name (DateFmt.short day loc.Language)
        | "avoid", NoteArg.Places places -> I18n.arg name (String.concat "; " places)
        | _, NoteArg.Number v -> I18n.numberArg name v
        | _, NoteArg.Text s -> I18n.arg name s
        | _, NoteArg.Places places -> I18n.arg name (String.concat "," places)
        // A null: the only one the catalog reads is the bacteria count.
        | "enterococci_per_100ml", NoteArg.Other -> I18n.arg name "na"
        | _, NoteArg.Other -> I18n.arg name "null"

    let text (note: Note) (english: string option) (loc: Locale) : string =
        let args =
            note.Args |> Map.toList |> List.map (fun (name, arg) -> toArg loc name arg)

        let args =
            if args |> List.exists (fun (k, _) -> k = "enterococci_per_100ml") then
                args
            else
                I18n.arg "enterococci_per_100ml" "na" :: args

        let code = NoteCode.toString note.Code
        let key = "note." + code
        let out = I18n.t loc key args

        if out <> key then
            out
        else
            match english with
            | Some line -> line
            | None -> code

    /// The lines for a shown hour. A board with no note codes (schema 1) has only the English lines.
    let ofShown (shown: Shown) (loc: Locale) : string list =
        match shown.NoteCodes with
        | [] -> shown.Notes
        | codes -> codes |> List.mapi (fun i code -> text code (List.tryItem i shown.Notes) loc)
