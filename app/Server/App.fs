namespace Marola.Server

open System
open System.Diagnostics
open System.IO.Compression
open System.Threading
open System.Threading.RateLimiting
open System.Threading.Tasks
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Http
open Microsoft.AspNetCore.Http.Features
open Microsoft.AspNetCore.RateLimiting
open Microsoft.AspNetCore.ResponseCompression
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Logging

module App =

    /// Every request body: 1 MB. The study upload of a later run sets its own limit on its own route.
    let bodyLimit = 1_048_576L

    /// A page load fetches a few dozen files, so the general limit is wide; it stops a flood, not a visitor.
    let generalPermits = 300
    let generalWindow = TimeSpan.FromMinutes 1.

    /// POST endpoints: 10 in 10 minutes per client.
    let strictPermits = 10
    let strictWindow = TimeSpan.FromMinutes 10.

    let private fixedWindow (permits: int) (window: TimeSpan) (key: string) =
        RateLimitPartition.GetFixedWindowLimiter(
            key,
            fun _ -> FixedWindowRateLimiterOptions(PermitLimit = permits, Window = window, QueueLimit = 0)
        )

    let private textTypes =
        [ "text/html"
          "text/css"
          "text/plain"
          "text/javascript"
          "application/json"
          "application/xml"
          "image/svg+xml" ]

    let private plain (ctx: HttpContext) (status: int) (text: string) : Task =
        ctx.Response.StatusCode <- status
        ctx.Response.ContentType <- "text/plain; charset=utf-8"
        ctx.Response.WriteAsync text

    let createBuilder (config: Config) : WebApplicationBuilder =
        let builder = WebApplication.CreateBuilder([||])

        // Console, one JSON object per line. The hosting log line of ASP.NET carries the query string,
        // so the framework logs only warnings and `requestLog` writes the one line this server keeps.
        builder.Logging.ClearProviders() |> ignore

        builder.Logging.AddJsonConsole(fun (o: Microsoft.Extensions.Logging.Console.JsonConsoleFormatterOptions) ->
            o.IncludeScopes <- false
            o.UseUtcTimestamp <- true
            o.TimestampFormat <- "yyyy-MM-ddTHH:mm:ssZ ")
        |> ignore

        builder.Logging.AddFilter("Microsoft.AspNetCore", LogLevel.Warning) |> ignore

        builder.Services.AddSingleton<Config>(config) |> ignore

        builder.Services.AddResponseCompression(fun (o: ResponseCompressionOptions) ->
            o.EnableForHttps <- true
            o.Providers.Add<BrotliCompressionProvider>()
            o.Providers.Add<GzipCompressionProvider>()
            o.MimeTypes <- textTypes)
        |> ignore

        builder.Services.Configure<BrotliCompressionProviderOptions>(fun (o: BrotliCompressionProviderOptions) ->
            o.Level <- CompressionLevel.Fastest)
        |> ignore

        builder.Services.Configure<GzipCompressionProviderOptions>(fun (o: GzipCompressionProviderOptions) ->
            o.Level <- CompressionLevel.Fastest)
        |> ignore

        // A message is at most 4000 characters: a form field of 8000 is already an abuse.
        builder.Services.Configure<FormOptions>(fun (o: FormOptions) ->
            o.ValueLengthLimit <- 8000
            o.ValueCountLimit <- 20)
        |> ignore

        builder.Services.AddRateLimiter(fun (o: RateLimiterOptions) ->
            o.RejectionStatusCode <- StatusCodes.Status429TooManyRequests

            o.GlobalLimiter <-
                PartitionedRateLimiter.Create<HttpContext, string>(fun ctx ->
                    fixedWindow generalPermits generalWindow (Security.requestKey ctx))

            o.AddPolicy(
                "strict",
                fun (ctx: HttpContext) -> fixedWindow strictPermits strictWindow (Security.requestKey ctx)
            )
            |> ignore

            o.OnRejected <-
                Func<OnRejectedContext, CancellationToken, ValueTask>(fun rejected token ->
                    let ctx = rejected.HttpContext

                    match rejected.Lease.TryGetMetadata MetadataName.RetryAfter with
                    | true, after -> ctx.Response.Headers.RetryAfter <- string (int after.TotalSeconds)
                    | _ -> ()

                    ValueTask(plain ctx 429 "too many requests\n")))
        |> ignore

        builder

    let private requestLog (log: ILogger) =
        Func<HttpContext, RequestDelegate, Task>(fun ctx next ->
            task {
                let started = Stopwatch.GetTimestamp()
                do! next.Invoke ctx
                // Method, path without the query, status and time. No address, no query, no body (LGPD).
                let path = ctx.Request.Path.Value

                let path =
                    if not (isNull path) && path.Length > 200 then
                        path.Substring(0, 200)
                    else
                        path

                log.LogInformation(
                    "{Method} {Path} {Status} {ElapsedMs}",
                    ctx.Request.Method,
                    path,
                    ctx.Response.StatusCode,
                    Stopwatch.GetElapsedTime(started).TotalMilliseconds
                )
            })

    let private bodyGuard =
        Func<HttpContext, RequestDelegate, Task>(fun ctx next ->
            if
                ctx.Request.ContentLength.HasValue
                && ctx.Request.ContentLength.Value > bodyLimit
            then
                plain ctx 413 "payload too large\n"
            else
                next.Invoke ctx)

    /// Creates the database, builds the app and adds the pipeline. Not started: a test starts it on
    /// the test host, Program on Kestrel.
    let build (builder: WebApplicationBuilder) (config: Config) : WebApplication =
        Store.init config.Db
        let app = builder.Build()
        let logs = app.Services.GetRequiredService<ILoggerFactory>()

        // Order matters. Headers first, so every response carries them (also an error or a 429).
        app.Use Security.middleware |> ignore
        app.Use(requestLog (logs.CreateLogger "Marola.Request")) |> ignore

        // No detail and no stack trace to the client; the exception goes to the log.
        app.UseExceptionHandler(fun (errors: IApplicationBuilder) ->
            errors.Run(fun ctx -> plain ctx 500 "internal server error\n"))
        |> ignore

        app.UseResponseCompression() |> ignore
        app.UseRateLimiter() |> ignore
        app.Use bodyGuard |> ignore

        let contactLog = logs.CreateLogger "Marola.Contact"

        // /en/contact is the English form's action: the same handler, which answers in that language.
        for route in [ "/contact"; "/en/contact" ] do
            app
                .MapPost(route, Func<HttpContext, Task<IResult>>(Contact.handle config contactLog))
                .RequireRateLimiting("strict")
            |> ignore

        app.MapFallback("{**path}", Func<HttpContext, IResult>(Files.handle config))
        |> ignore

        app
