namespace Marola.Server

open System
open System.Collections.Generic
open System.IO
open System.Text
open System.Threading.Tasks
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Http
open Microsoft.AspNetCore.Http.Features
open Microsoft.AspNetCore.Routing
open Microsoft.AspNetCore.WebUtilities
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Logging
open Microsoft.Extensions.Primitives
open Microsoft.Net.Http.Headers
open Marola.Study

/// `/api/v1`: submit, list and read studies, and the PDF route. Everything a client reads is built from
/// `Marola.Study`; nothing it sends reaches a header, a log line or a path except a validated id or hash.
module StudyApi =

    /// The body of the upload route: the file (20 MB), the text fields and the multipart framing.
    let uploadLimit = 21L * 1024L * 1024L

    let apiPath = "/api/v1/studies"
    let minAccountAge = TimeSpan.FromDays 7.
    let perKeyUnits = 90
    let realCost = 3
    let dryCost = 1
    let keyWindow = TimeSpan.FromMinutes 1.
    let gapBetween = TimeSpan.FromMinutes 10.
    let perDay = 10L
    let maxParts = 20
    let maxFieldBytes = 20_000

    /// Fixed window per key: 30 real submissions a minute, a dry run counts a third. In memory: a restart resets it.
    type KeyRates() =
        let table = Dictionary<string, struct (DateTimeOffset * int)>()

        member _.TryTake(key: string, cost: int, now: DateTimeOffset) : bool =
            lock table (fun () ->
                if table.Count > 10_000 then
                    for stale in
                        table
                        |> Seq.filter (fun kv -> let struct (s, _) = kv.Value in now - s >= keyWindow)
                        |> Seq.toList do
                        table.Remove stale.Key |> ignore

                let struct (start, used) =
                    match table.TryGetValue key with
                    | true, (struct (s, _) as v) when now - s < keyWindow -> v
                    | _ -> struct (now, 0)

                if used + cost > perKeyUnits then
                    table[key] <- struct (start, used)
                    false
                else
                    table[key] <- struct (start, used + cost)
                    true)

    let private clock (ctx: HttpContext) =
        ctx.RequestServices.GetRequiredService<TimeProvider>().GetUtcNow()

    let private writeJson (ctx: HttpContext) (status: int) (cache: string) (json: Json) : Task =
        ctx.Response.StatusCode <- status
        ctx.Response.ContentType <- "application/json; charset=utf-8"
        ctx.Response.Headers.CacheControl <- cache
        ctx.Response.WriteAsync(render json)

    let private failJson (ctx: HttpContext) (status: int) (field: string) (code: string) (message: string) : Task =
        writeJson
            ctx
            status
            "no-store"
            (errorsJson
                [ { Field = field
                    Code = code
                    Message = message } ])

    /// The 413 of the body guard, in the JSON shape of the API.
    let tooLarge (ctx: HttpContext) : Task =
        failJson ctx 413 "request" "too_large" "the request is larger than 21 MB"

    // ---- reading the upload -------------------------------------------------------------------------

    type private Upload =
        {
            Fields: Map<string, string>
            Pdf: Result<PdfIntake.Received, FieldError> option
            Errors: FieldError list
            /// The gate refused the request: the web form posted no valid CSRF token.
            Denied: bool
        }

    let private fieldNames =
        set
            [ "title"
              "authors"
              "abstract"
              "area"
              "topic"
              "sources"
              "repository"
              "licence"
              "rights"
              "ai_models"
              "ai_contribution"
              "ai_process" ]

    let private strict = UTF8Encoding(false, true)

    /// A text part, at most `maxFieldBytes`, strict UTF-8.
    let private readText (section: MultipartSection) : Task<Result<string, string>> =
        task {
            use buffer = new MemoryStream()
            let chunk = Array.zeroCreate<byte> 4096
            let mutable go = true
            let mutable tooBig = false

            while go do
                let! n = section.Body.ReadAsync(chunk, 0, chunk.Length)

                if n = 0 then
                    go <- false
                elif buffer.Length + int64 n > int64 maxFieldBytes then
                    tooBig <- true
                    go <- false
                else
                    buffer.Write(chunk, 0, n)

            if tooBig then
                return Error "too_long"
            else
                try
                    return Ok(strict.GetString(buffer.GetBuffer(), 0, int buffer.Length))
                with :? ArgumentException ->
                    return Error "invalid_utf8"
        }

    let private readUpload
        (config: Config)
        (store: bool)
        (pending: ResizeArray<PdfIntake.Received>)
        (ctx: HttpContext)
        (boundary: string)
        (extra: Set<string>)
        (gate: Map<string, string> -> bool)
        : Task<Upload> =
        task {
            let reader =
                MultipartReader(
                    boundary,
                    ctx.Request.Body,
                    HeadersCountLimit = 8,
                    HeadersLengthLimit = 4096,
                    BodyLengthLimit = uploadLimit
                )

            let mutable fields = Map.empty
            let mutable pdf = None
            let errors = ResizeArray<FieldError>()
            let seen = HashSet<string>()
            let mutable parts = 0
            let mutable denied = false
            let mutable go = true

            let add field code message =
                errors.Add
                    { Field = field
                      Code = code
                      Message = message }

            while go do
                let! section = reader.ReadNextSectionAsync()

                if isNull section then
                    go <- false
                else
                    parts <- parts + 1

                    let name =
                        match section.GetContentDispositionHeader() with
                        | null -> ""
                        | cd ->
                            if cd.Name.HasValue then
                                HeaderUtilities.RemoveQuotes(cd.Name).Value
                            else
                                ""

                    if parts > maxParts then
                        add "request" "too_many_parts" ("at most " + string maxParts + " parts")
                        go <- false
                    elif not (seen.Add name) then
                        // The name is not echoed: it is attacker text.
                        add "request" "duplicate_field" "a field name appears twice"
                    elif name = "pdf" && not (gate fields) then
                        // Nothing of the file is read: the token comes first in the form, and a post without it stores nothing.
                        denied <- true
                        go <- false
                    elif name = "pdf" then
                        let! r = PdfIntake.receive config store section.Body
                        pdf <- Some r
                        // Kept for the caller: a later part may fail, and the temp file must not stay.
                        r |> Result.iter pending.Add
                    elif fieldNames.Contains name || extra.Contains name then
                        let! text = readText section

                        match text with
                        | Ok t -> fields <- Map.add name t fields
                        | Error code ->
                            add
                                name
                                code
                                (name
                                 + (if code = "too_long" then
                                        " is too long"
                                    else
                                        " is not valid UTF-8"))
                    else
                        add "request" "unknown_field" "an unknown field was sent"

            return
                { Fields = fields
                  Pdf = pdf
                  Errors = List.ofSeq errors
                  Denied = denied || not (gate fields) }
        }

    // ---- POST -----------------------------------------------------------------------------------------

    let private bearer (ctx: HttpContext) : string =
        let h = ctx.Request.Headers.Authorization.ToString()

        if h.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) then
            h.Substring(7).Trim()
        else
            ""

    // ---- the intake: one path for the API and the web form ---------------------------------------------

    type Failure =
        {
            Status: int
            RetryAfter: string option
            Errors: FieldError list
            /// The id of the study this account already sent (a 409).
            Existing: string option
        }

    type Outcome =
        | Failed of Failure
        | DryRun of PdfIntake.Received * Submission
        | Created of Record

    let private failure status retry field code message : Outcome =
        Failed
            { Status = status
              RetryAfter = retry
              Errors =
                [ { Field = field
                    Code = code
                    Message = message } ]
              Existing = None }

    /// Everything after the caller is known: account age, rates, the multipart body, the fields, the file,
    /// the duplicate and the quota, then the insert. The API (bearer key) and the web form (session) both call it.
    /// `rateKey` names the caller in the per-minute limiter. `extra` are the form fields besides the study's own
    /// (the web form's `csrf`); `gate` sees the fields read so far, before the file is stored: a `false` stops the
    /// request with a 403, so a post with no token never writes a file. Returns the text fields too, so the form
    /// can show them again.
    let intake
        (config: Config)
        (rates: KeyRates)
        (log: ILogger)
        (ctx: HttpContext)
        (account: StudyStore.Account)
        (rateKey: string)
        (extra: Set<string>)
        (gate: Map<string, string> -> bool)
        : Task<Outcome * Map<string, string>> =
        task {
            let now = clock ctx
            let dry = ctx.Request.Query["dry_run"].ToString() = "1"
            let nothing = Map.empty<string, string>

            let stop (o: Outcome) = o, nothing

            if
                (match DateTimeOffset.TryParse account.CreatedGithubUtc with
                 | true, created -> now - created < minAccountAge
                 | _ -> true)
            then
                return
                    stop (failure 403 None "request" "account_too_new" "the GitHub account must be at least 7 days old")
            elif not (rates.TryTake(rateKey, (if dry then dryCost else realCost), now)) then
                return
                    stop (
                        failure
                            429
                            (Some "60")
                            "request"
                            "rate_limited"
                            "more than 30 requests a minute for this key (a dry run counts a third)"
                    )
            elif
                isNull ctx.Request.ContentType
                || not (ctx.Request.ContentType.StartsWith("multipart/form-data", StringComparison.OrdinalIgnoreCase))
            then
                return stop (failure 415 None "request" "unsupported_media_type" "send multipart/form-data")
            elif StudyStore.countSince config.Db account.GithubId (now - gapBetween) > 0L then
                return
                    stop (
                        failure
                            429
                            (Some(string (int gapBetween.TotalSeconds)))
                            "request"
                            "too_soon"
                            "one submission per account every 10 minutes"
                    )
            elif
                StudyStore.countSince config.Db account.GithubId (now - TimeSpan.FromDays 1.)
                >= perDay
            then
                return
                    stop (failure 429 (Some "86400") "request" "daily_limit" "10 submissions per account in 24 hours")
            else
                let boundary =
                    match MediaTypeHeaderValue.TryParse ctx.Request.ContentType with
                    | true, mt -> HeaderUtilities.RemoveQuotes(mt.Boundary).Value
                    | _ -> null

                if String.IsNullOrEmpty boundary || boundary.Length > 70 then
                    return
                        stop (
                            failure
                                400
                                None
                                "request"
                                "malformed_multipart"
                                "the multipart boundary is missing or too long"
                        )
                else
                    match ctx.Features.Get<IHttpMaxRequestBodySizeFeature>() with
                    | null -> ()
                    | f when not f.IsReadOnly -> f.MaxRequestBodySize <- Nullable uploadLimit
                    | _ -> ()

                    let pending = ResizeArray<PdfIntake.Received>()

                    let! outcome =
                        task {
                            try
                                let! u = readUpload config (not dry) pending ctx boundary extra gate
                                return Ok u
                            with
                            | :? BadHttpRequestException as e when e.StatusCode = 413 ->
                                pending |> Seq.iter PdfIntake.discard
                                return Error(413, "too_large", "the request is larger than 21 MB")
                            // BadHttpRequestException is an IOException too: this arm takes the other cases.
                            | :? InvalidDataException
                            | :? IOException ->
                                pending |> Seq.iter PdfIntake.discard

                                return
                                    Error(400, "malformed_multipart", "the multipart body is malformed or over a limit")
                        }

                    match outcome with
                    | Error(status, code, message) -> return stop (failure status None "request" code message)
                    | Ok upload when upload.Denied ->
                        pending |> Seq.iter PdfIntake.discard
                        return (failure 403 None "request" "csrf" "the form token is missing or wrong", upload.Fields)
                    | Ok upload ->
                        let received =
                            upload.Pdf
                            |> Option.bind (function
                                | Ok r -> Some r
                                | Error _ -> None)

                        let discard () =
                            received |> Option.iter PdfIntake.discard

                        let checkedFields = validate (fun k -> Map.tryFind k upload.Fields)

                        let pdfErrors =
                            match upload.Pdf with
                            | None ->
                                [ { Field = "pdf"
                                    Code = "required"
                                    Message = "send the PDF in the field pdf" } ]
                            | Some(Error e) -> [ e ]
                            | Some(Ok _) -> []

                        let errors =
                            upload.Errors
                            @ (match checkedFields with
                               | Error es -> es
                               | Ok _ -> [])
                            @ pdfErrors

                        let done' o = o, upload.Fields

                        if not (List.isEmpty errors) then
                            discard ()

                            let tooLarge =
                                errors |> List.exists (fun e -> e.Field = "pdf" && e.Code = "too_large")

                            return
                                done' (
                                    Failed
                                        { Status = (if tooLarge then 413 else 400)
                                          RetryAfter = None
                                          Errors = errors
                                          Existing = None }
                                )
                        else
                            let r = received.Value

                            let submission =
                                match checkedFields with
                                | Ok s -> s
                                | Error _ -> failwith "unreachable"

                            match StudyStore.findByHash config.Db account.GithubId r.Sha256 with
                            | Some old ->
                                discard ()

                                return
                                    done' (
                                        Failed
                                            { Status = 409
                                              RetryAfter = None
                                              Errors =
                                                [ { Field = "pdf"
                                                    Code = "duplicate"
                                                    Message = "this account already sent this file" } ]
                                              Existing = Some old }
                                    )
                            | None when not (PdfIntake.fitsQuota config r) ->
                                discard ()
                                log.LogWarning "study store quota reached"

                                return
                                    done' (
                                        failure
                                            507
                                            None
                                            "pdf"
                                            "quota_exceeded"
                                            "the study store is full; try again later and tell the board"
                                    )
                            | None when dry -> return done' (DryRun(r, submission))
                            | None ->
                                match StudyStore.insertStudy config.Db now account r.Sha256 submission with
                                | None ->
                                    // Lost a race with the same upload: the other request owns the row.
                                    discard ()

                                    return
                                        done' (failure 409 None "pdf" "duplicate" "this account already sent this file")
                                | Some record ->
                                    PdfIntake.commit config r
                                    // Ids only: the title, the abstract and the file name are the author's.
                                    log.LogInformation(
                                        "study stored {StudyId} account {AccountId}",
                                        record.Id,
                                        account.GithubId
                                    )

                                    return done' (Created record)
        }

    let private writeFailure (ctx: HttpContext) (f: Failure) : Task =
        f.RetryAfter |> Option.iter (fun v -> ctx.Response.Headers.RetryAfter <- v)

        match f.Existing with
        | Some old ->
            writeJson
                ctx
                f.Status
                "no-store"
                (JObject
                    [ "errors",
                      JArray
                          [ JObject
                                [ "field", JString "pdf"
                                  "code", JString "duplicate"
                                  "message", JString "this account already sent this file" ] ]
                      "id", JString old
                      "url", JString(urlOf old) ])
        | None -> writeJson ctx f.Status "no-store" (errorsJson f.Errors)

    let private submit (config: Config) (rates: KeyRates) (log: ILogger) (ctx: HttpContext) : Task =
        task {
            let key = bearer ctx

            match StudyStore.verifyKey config.Db key with
            | None ->
                ctx.Response.Headers.WWWAuthenticate <- "Bearer"

                return!
                    failJson ctx 401 "request" "unauthorized" "send a valid API key as: Authorization: Bearer msk_..."
            | Some account ->
                let! outcome, _ = intake config rates log ctx account (StudyStore.hashKey key) Set.empty (fun _ -> true)

                match outcome with
                | Failed f -> return! writeFailure ctx f
                | DryRun(r, submission) ->
                    return!
                        writeJson
                            ctx
                            200
                            "no-store"
                            (JObject
                                [ "dry_run", JBool true
                                  "ok", JBool true
                                  "sha256", JString r.Sha256
                                  "size_bytes", JInt r.Size
                                  "status", JString "public"
                                  "review", JString "not reviewed"
                                  "notice", JString notice
                                  "submission", JObject(submissionJson submission) ])
                | Created record -> return! writeJson ctx 201 "no-store" (receiptJson record)
        }

    // ---- GET ------------------------------------------------------------------------------------------

    let private list (config: Config) (ctx: HttpContext) : Task =
        let q = ctx.Request.Query
        let errors = ResizeArray<FieldError>()

        let bad field message =
            errors.Add
                { Field = field
                  Code = "invalid"
                  Message = message }

        let opt name parse values =
            match q[name].ToString() with
            | "" -> None
            | v ->
                match parse v with
                | Some x -> Some x
                | None ->
                    bad name (name + " must be one of: " + String.concat ", " values)
                    None

        let area = opt "area" parseArea areaValues
        let topic = opt "topic" parseTopic topicValues

        let before =
            match q["before"].ToString() with
            | "" -> None
            | b when validId b -> Some b
            | _ ->
                bad "before" "before must be a study id"
                None

        let limit =
            match q["limit"].ToString() with
            | "" -> 20
            | l ->
                match Int32.TryParse l with
                | true, n when n >= 1 && n <= 50 -> n
                | _ ->
                    bad "limit" "limit must be 1 to 50"
                    20

        if errors.Count > 0 then
            writeJson ctx 400 "no-store" (errorsJson (List.ofSeq errors))
        else
            let studies = StudyStore.listStudies config.Db area topic before limit

            writeJson
                ctx
                200
                "public, max-age=60"
                (JObject
                    [ "notice", JString notice
                      "studies", JArray(studies |> List.map recordJson)
                      "next_before",
                      (if List.length studies = limit then
                           JString (List.last studies).Id
                       else
                           JNull) ])

    let private one (config: Config) (ctx: HttpContext) (id: string) : Task =
        match
            (if validId id then
                 StudyStore.getStudy config.Db id
             else
                 None)
        with
        | None -> failJson ctx 404 "id" "not_found" "no study with this id"
        | Some r -> writeJson ctx 200 "public, max-age=60" (recordJson r)

    /// The file of a public study. `sandbox` and `default-src 'none'` replace the page's CSP: whatever
    /// a PDF viewer would run runs with no origin and no network.
    let pdf (config: Config) (log: ILogger) (ctx: HttpContext) (file: string) : Task =
        let id =
            if file.EndsWith ".pdf" then
                file.Substring(0, file.Length - 4)
            else
                ""

        match
            (if validId id then
                 StudyStore.getStudy config.Db id
             else
                 None)
        with
        | Some r when r.Status = Public ->
            let path = PdfIntake.pathOf config r.Sha256

            if File.Exists path then
                let h = ctx.Response.Headers
                ctx.Response.ContentType <- "application/pdf"
                let disposition: string = "inline; filename=\"" + id + ".pdf\""
                h.ContentDisposition <- disposition
                h["X-Content-Type-Options"] <- "nosniff"
                h["Content-Security-Policy"] <- "sandbox; default-src 'none'"
                h.CacheControl <- "public, max-age=3600"
                ctx.Response.SendFileAsync path
            else
                log.LogError("study file missing {StudyId}", id)
                failJson ctx 404 "id" "not_found" "no study with this id"
        | _ -> failJson ctx 404 "id" "not_found" "no study with this id"

    // ---- skill.md -------------------------------------------------------------------------------------

    let skill: string =
        let levels =
            levelValues
            |> List.map (fun v -> "- `" + v + "`: " + levelMeaning (parseLevel v).Value)
            |> String.concat "\n"

        $"""# Submit a study to marola

marola publishes studies by anyone with a GitHub account that is at least 7 days old. A study is public at once
and is labelled "not reviewed, not medical advice". The board can hide a study later; it then keeps its hash,
its date and a reason. Only open licences are accepted, because marola hosts the file.

## Get a key

Sign in with GitHub on marola.dev and make an API key (`msk_...`). The key is shown once. An account has at most 3 active keys.
Send it as `Authorization: Bearer $MAROLA_KEY`. Never put a key in a repository or a log.

## Endpoint

`POST https://marola.dev/api/v1/studies` with `multipart/form-data`. Add `?dry_run=1` to check everything
(the file and the limits too) with nothing stored.

| field | rule |
|---|---|
| `title` | 5 to 200 characters, one line |
| `authors` | 1 to 20 lines. One author per line: `Name` or `Name | 0000-0002-1825-0097` (an ORCID iD with its check digit). A name has 2 to 120 characters |
| `abstract` | 100 to 4000 characters |
| `area` | {String.concat ", " areaValues} |
| `topic` | {String.concat ", " topicValues} |
| `sources` | 0 to 10 https links, one per line |
| `repository` | optional https link |
| `licence` | {String.concat ", " licenceValues}. Default `CC-BY-4.0` |
| `rights` | `true`: you have the right to publish this file under that licence |
| `ai_models` | optional, up to 300 characters |
| `ai_contribution` | one of the levels below |
| `ai_process` | up to 1500 characters. Required unless `ai_contribution` is `none` |
| `pdf` | the file: a PDF of at most 20 MB |

Each field appears once. Text is UTF-8. Control characters other than newline and tab are removed.

## AI contribution levels

{levels}

## The PDF

It must start with `{"%"}PDF-` and end with `startxref` and `{"%%"}EOF`. marola refuses a file that has one of the names
`/Launch`, `/JavaScript`, `/JS`, `/EmbeddedFile` (also written with `#xx` escapes) or an `/OpenAction` whose value is
an action. Export the PDF again without scripts, attachments or launch actions.

## Examples

```
curl -sS -H "Authorization: Bearer $MAROLA_KEY" "https://marola.dev/api/v1/studies?dry_run=1" \
  -F title="Enterococcus at Leblon, 2025" -F "authors=Ana Silva | 0000-0002-1825-0097" \
  -F "abstract=<abstract.txt" -F area=rio -F topic=water-quality -F rights=true \
  -F ai_contribution=none -F pdf=@study.pdf
```

Drop `?dry_run=1` to publish. Success is `201` with `id`, `url`, `pdf_url`, `sha256`, `received_utc`, `status` and `record`.

```
curl -sS "https://marola.dev/api/v1/studies?area=rio&topic=water-quality&limit=20"
curl -sS "https://marola.dev/api/v1/studies/<id>"
```

## Errors

`400` returns `{{"errors":[{{"field","code","message"}}]}}` with every error at once. The codes are
`required`, `too_short`, `too_long`, `too_many`, `invalid`, `unknown_value`, `bad_name`, `bad_orcid`, `bad_link`,
`must_be_true`, `invalid_utf8`, `duplicate_field`, `unknown_field`, `too_many_parts`, `malformed_multipart`,
and for the file `not_pdf`, `truncated`, `active_content`.
`401` bad or missing key. `403` the account is under 7 days old. `409` this account sent this file already (the answer has the old `id`).
`413` the file or the request is too large. `415` not multipart. `429` too many requests: one real submission per account every 10 minutes and 10 a day,
30 requests a minute per key (a dry run counts a third); read `Retry-After`. `507` the study store is full.
"""

    // ---- wiring ---------------------------------------------------------------------------------------

    let map (app: WebApplication) (config: Config) (logs: ILoggerFactory) : unit =
        let log = logs.CreateLogger "Marola.Studies"
        let rates = KeyRates()

        app.MapPost(apiPath, Func<HttpContext, Task>(submit config rates log)) |> ignore
        app.MapGet(apiPath, Func<HttpContext, Task>(list config)) |> ignore

        app.MapGet(
            apiPath + "/{id}",
            Func<HttpContext, Task>(fun ctx -> one config ctx (ctx.Request.RouteValues["id"].ToString()))
        )
        |> ignore

        app.MapGet(
            "/api/v1/skill.md",
            Func<HttpContext, Task>(fun ctx ->
                ctx.Response.ContentType <- "text/plain; charset=utf-8"
                ctx.Response.Headers.CacheControl <- "public, max-age=300"
                ctx.Response.WriteAsync skill)
        )
        |> ignore
// `/studies/<id>.pdf` and the page `/studies/<id>` share a pattern: `Web.map` registers both and calls `pdf`.
