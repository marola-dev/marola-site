namespace Marola

/// Text and links that reach the page. It replaces app.js `esc()`, and adds the scheme check the
/// old `lore.source` link never had.
module Html =

    /// Escapes the five characters that matter in HTML text and in a quoted attribute. Elmish and
    /// Feliz do this for their own text and attributes; this is for the places that build markup
    /// by hand.
    let escapeHtml (text: string) : string =
        text
            .Replace("&", "&amp;")
            .Replace("<", "&lt;")
            .Replace(">", "&gt;")
            .Replace("\"", "&quot;")
            .Replace("'", "&#39;")

    let private isLetter (c: char) : bool =
        (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')

    let private isSchemeChar (c: char) : bool =
        isLetter c || (c >= '0' && c <= '9') || c = '+' || c = '-' || c = '.'

    /// RFC 3986: a letter, then letters, digits, "+", "-" or ".".
    let private validScheme (scheme: string) : bool =
        scheme.Length > 0 && isLetter scheme.[0] && Seq.forall isSchemeChar scheme

    let private hasControl (text: string) : bool =
        text |> Seq.exists (fun c -> c < '\u0020' || (c >= '\u007F' && c <= '\u009F'))

    let private trimControls (text: string) : string =
        let isEdge (c: char) = c <= '\u0020'
        let mutable start = 0
        let mutable stop = text.Length

        while start < stop && isEdge text.[start] do
            start <- start + 1

        while stop > start && isEdge text.[stop - 1] do
            stop <- stop - 1

        text.Substring(start, stop - start)

    /// A link a page may put in an `href`: only `https:`, `http:` and `mailto:`. It reads the URL
    /// the way a browser does, which drops tab and newline anywhere and the control characters and
    /// spaces around it, so "java\tscript:..." and " javascript:..." cannot slip through. The
    /// result is that cleaned URL. It still needs attribute escaping where it is written.
    let safeHref (url: string) : string option =
        let cleaned =
            url.Replace("\t", "").Replace("\n", "").Replace("\r", "") |> trimControls

        match cleaned.IndexOf ':' with
        | -1 -> None
        | i ->
            let scheme = cleaned.Substring(0, i)
            let rest = cleaned.Substring(i + 1)

            if
                rest <> ""
                && validScheme scheme
                && List.contains (scheme.ToLowerInvariant()) [ "https"; "http"; "mailto" ]
                && not (hasControl cleaned)
            then
                Some cleaned
            else
                None
