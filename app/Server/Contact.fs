namespace Marola.Server

open System
open System.IO
open System.Text.RegularExpressions
open System.Threading.Tasks
open Microsoft.AspNetCore.Http
open Microsoft.Extensions.Logging

/// The contact form: `POST /contact` stores the message in SQLite. The board reads it with `marola-server inbox`.
module Contact =

    let minMessage = 10
    let maxMessage = 4000

    // One `@`, no spaces, quotes, brackets or commas in the local part, and a dotted domain of
    // letters, digits and hyphens. Not the whole RFC: a mistyped address must fail, and nothing
    // here sends mail, so an exotic one is no loss.
    let private emailShape =
        Regex(
            @"^[^@\s<>,;:""()\[\]\\]{1,64}@[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$",
            RegexOptions.Compiled
        )

    let validateEmail (raw: string) : Result<string, string> =
        let email = if isNull raw then "" else raw.Trim()

        if email.Length = 0 || email.Length > 254 || not (emailShape.IsMatch email) then
            Error "email"
        else
            Ok email

    // Tab and the newlines are the only control characters a message may carry: the board prints the
    // body on a terminal, and NUL breaks SQLite text.
    let private hasBadControl (s: string) =
        s
        |> Seq.exists (fun c -> Char.IsControl c && c <> '\n' && c <> '\r' && c <> '\t')

    let validateMessage (raw: string) : Result<string, string> =
        let message = if isNull raw then "" else raw.Trim()

        if
            message.Length < minMessage
            || message.Length > maxMessage
            || hasBadControl message
        then
            Error "message"
        else
            Ok message

    /// The Host header and the Origin (or, failing it, the Referer) must name the same site. A browser
    /// always sends Origin on a cross-site POST and a page cannot forge it, so no token is needed
    /// (the page is static and cannot carry one). nginx must pass the public host: `proxy_set_header Host $host`.
    let sameSite (host: string) (origin: string) (referer: string) : bool =
        let authority (value: string) =
            match Uri.TryCreate(value, UriKind.Absolute) with
            | true, uri when uri.Scheme = "https" || uri.Scheme = "http" -> Some(uri.Authority)
            | _ -> None

        let claimed = if String.IsNullOrEmpty origin then referer else origin

        match authority claimed, authority ("https://" + host) with
        | Some theirs, Some ours -> String.Equals(theirs, ours, StringComparison.OrdinalIgnoreCase)
        | _ -> false

    let private plain (status: int) (text: string) : IResult =
        Results.Text(text + "\n", "text/plain; charset=utf-8", Text.Encoding.UTF8, Nullable status)

    let private formType = "application/x-www-form-urlencoded"

    let handle (config: Config) (log: ILogger) (ctx: HttpContext) : Task<IResult> =
        task {
            let request = ctx.Request
            let header (name: string) = request.Headers[name].ToString()

            if not (sameSite (header "Host") (header "Origin") (header "Referer")) then
                return plain 403 "forbidden"
            elif
                not (
                    request.ContentType |> isNull |> not
                    && request.ContentType.StartsWith(formType, StringComparison.OrdinalIgnoreCase)
                )
            then
                return plain 415 "unsupported media type"
            else
                let! form =
                    task {
                        try
                            let! f = request.ReadFormAsync()
                            return Ok f
                        with
                        | :? InvalidDataException -> return Error 400
                        // Kestrel's own limit (413 for a body over 1 MB) surfaces here.
                        | :? BadHttpRequestException as e -> return Error e.StatusCode
                    }

                match form with
                | Error status -> return plain status "bad request"
                | Ok form ->
                    let field (name: string) = form[name].ToString()

                    if field "website" <> "" then
                        // A bot fills the hidden field. It gets a plain 200 and nothing is stored.
                        return plain 200 "ok"
                    else
                        match validateEmail (field "email"), validateMessage (field "message") with
                        | Ok email, Ok message ->
                            let id = Store.insert config.Db DateTimeOffset.UtcNow email message
                            // The id only: the address and the text are personal data.
                            log.LogInformation("contact message stored {MessageId}", id)
                            ctx.Response.Headers.Location <- "/contact?sent=1"
                            return Results.StatusCode 303
                        | Error bad, _
                        | _, Error bad -> return plain 400 ("invalid " + bad)
        }
