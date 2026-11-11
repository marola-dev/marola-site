namespace Marola.Server

open System
open System.IO
open System.Text.RegularExpressions
open Microsoft.AspNetCore.Http
open Microsoft.Net.Http.Headers

/// Static files from two roots, read-only. The URL path is checked against an allowlist before it
/// touches the disk, so no encoding trick has to be recognised: it is only never in the list.
module Files =

    let private safeChar (c: char) =
        Char.IsAsciiLetterOrDigit c || c = '.' || c = '-' || c = '_'

    /// A segment is safe when it is not empty, is not hidden (no leading dot, which also rules out `.` and
    /// `..`) and has only letters, digits, `.`, `-` and `_`. That excludes `/`, `\`, `%`, NUL and `:`.
    let private safeSegment (s: string) =
        s.Length > 0 && s[0] <> '.' && s.Length <= 128 && Seq.forall safeChar s

    /// The segments of a URL path, or None if the path could leave the roots or reach a hidden file.
    /// A path that ends in `/` (and `/` itself) names the `index.html` of that folder.
    let segments (path: string) : string list option =
        if isNull path || path.Length = 0 || path[0] <> '/' || path.Length > 512 then
            None
        else
            let parts = path.Substring(1).Split '/' |> List.ofArray

            let parts =
                match List.rev parts with
                | "" :: before -> List.rev ("index.html" :: before)
                | _ -> parts

            if List.forall safeSegment parts then Some parts else None

    let private under (root: string) (parts: string list) =
        Path.Combine(root, String.Join('/', parts))

    /// Where a path may live, in order. `/data/<x>` is the board data folder's first, so a deploy can
    /// replace the boards without rebuilding the page; the page's own `data/` (fixtures) is the fallback.
    let private candidates (config: Config) (parts: string list) : string list =
        match parts with
        | "data" :: rest when not rest.IsEmpty -> [ under config.Data rest; under config.Static parts ]
        | _ -> [ under config.Static parts ]

    /// The file to send for `path`, if any: the file itself, else `<path>.html` (so `/contact` finds
    /// `contact.html`). A folder is never listed.
    let resolve (config: Config) (path: string) : string option =
        match segments path with
        | None -> None
        | Some parts ->
            let withHtml =
                match List.rev parts with
                | last :: before when not (last.Contains '.') -> [ List.rev ((last + ".html") :: before) ]
                | _ -> []

            (parts :: withHtml)
            |> List.collect (candidates config)
            |> List.tryFind File.Exists

    let contentType (file: string) : string =
        match Path.GetExtension(file).ToLowerInvariant() with
        | ".html" -> "text/html; charset=utf-8"
        | ".js"
        | ".mjs" -> "text/javascript; charset=utf-8"
        | ".css" -> "text/css; charset=utf-8"
        | ".json" -> "application/json; charset=utf-8"
        | ".txt"
        | ".md" -> "text/plain; charset=utf-8"
        | ".xml" -> "application/xml; charset=utf-8"
        | ".svg" -> "image/svg+xml"
        | ".png" -> "image/png"
        | ".jpg"
        | ".jpeg" -> "image/jpeg"
        | ".webp" -> "image/webp"
        | ".ico" -> "image/x-icon"
        | ".woff2" -> "font/woff2"
        | ".woff" -> "font/woff"
        | ".mp3" -> "audio/mpeg"
        | _ -> "application/octet-stream"

    /// `name.<8 or more hex digits>.ext`: the file name carries its content hash, so it never changes.
    let private hashed = Regex(@"\.[0-9a-f]{8,}\.[a-z0-9]+$", RegexOptions.Compiled)

    let cacheControl (file: string) : string =
        let name = Path.GetFileName file

        match Path.GetExtension(name).ToLowerInvariant() with
        | _ when hashed.IsMatch name -> "public, max-age=31536000, immutable"
        | ".woff2"
        | ".woff"
        | ".png"
        | ".jpg"
        | ".jpeg"
        | ".webp"
        | ".ico"
        | ".svg" -> "public, max-age=86400"
        | _ -> "no-cache"

    let private plain (status: int) (text: string) : IResult =
        Results.Text(text, "text/plain; charset=utf-8", Text.Encoding.UTF8, Nullable status)

    let notFound: IResult = plain 404 "not found\n"

    /// The 404 page of the language the path is under (`404.html`, or `en/404.html` below `/en/`), sent with
    /// status 404. A build without pages has none, and the plain text answers.
    let private notFoundPage (config: Config) (path: string) : IResult =
        let page =
            if not (isNull path) && path.StartsWith "/en/" then
                [ "en"; "404.html" ]
            else
                [ "404.html" ]

        let file = under config.Static page

        if File.Exists file then
            Results.Text(File.ReadAllText file, "text/html; charset=utf-8", Text.Encoding.UTF8, Nullable 404)
        else
            notFound

    /// GET and HEAD only; `Results.File` answers `If-None-Match` and `If-Modified-Since` and sends no
    /// body for HEAD. The ETag is size plus mtime: cheap, and it changes with every deploy.
    let handle (config: Config) (ctx: HttpContext) : IResult =
        let request = ctx.Request

        if not (HttpMethods.IsGet request.Method || HttpMethods.IsHead request.Method) then
            ctx.Response.Headers.Allow <- "GET, HEAD"
            plain 405 "method not allowed\n"
        else
            match resolve config (request.Path.Value) with
            | None -> notFoundPage config request.Path.Value
            | Some file ->
                let info = FileInfo file
                let modified = DateTimeOffset(info.LastWriteTimeUtc)
                let etag = $"\"{info.Length:x}-{modified.ToUnixTimeSeconds():x}\""
                ctx.Response.Headers.CacheControl <- cacheControl file

                Results.File(file, contentType file, null, Nullable modified, EntityTagHeaderValue(etag), false)
