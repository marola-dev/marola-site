/// A site on the test host: the real pipeline, in memory, over a temporary tree.
module Marola.Server.Tests.Harness

open System
open System.IO
open System.Net
open System.Net.Http
open System.Threading.Tasks
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Hosting
open Microsoft.AspNetCore.Http
open Microsoft.AspNetCore.TestHost
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Logging
open Marola.Server

/// Keeps every log line, message and structured values, to check what the server writes.
type Capture() =
    let lines = ResizeArray<string>()
    member _.Lines = lines |> Seq.toList

    interface ILoggerProvider with
        member _.CreateLogger(_) =
            { new ILogger with
                member _.BeginScope _ = null
                member _.IsEnabled _ = true

                member _.Log(_, _, state, ex, formatter) =
                    let values =
                        match box state with
                        | :? seq<Collections.Generic.KeyValuePair<string, obj>> as pairs ->
                            pairs |> Seq.map (fun p -> string p.Value) |> String.concat " "
                        | _ -> ""

                    lock lines (fun () -> lines.Add(formatter.Invoke(state, ex) + " | " + values + " | " + string ex)) }

        member _.Dispose() = ()

/// Lets a test pick the peer address with a header; Kestrel gives the real one. Test-only: the header is
/// read here and nowhere in the server.
type PeerFilter() =
    interface IStartupFilter with
        member _.Configure(next) =
            Action<IApplicationBuilder>(fun app ->
                app.Use(
                    Func<HttpContext, RequestDelegate, Task>(fun ctx n ->
                        match ctx.Request.Headers["X-Test-Peer"].ToString() with
                        | "" -> ()
                        | peer -> ctx.Connection.RemoteIpAddress <- IPAddress.Parse peer

                        n.Invoke ctx)
                )
                |> ignore

                next.Invoke app)

/// A clock a test moves: the rate limits of the study API are in minutes and days.
type ManualClock(start: DateTimeOffset) =
    inherit TimeProvider()
    let mutable now = start
    override _.GetUtcNow() = now
    member _.Advance(by: TimeSpan) = now <- now + by
    member _.Now = now

/// The GitHub the server talks to in tests: the test sets `Respond`, and `Seen` keeps what was asked.
type FakeGithub() =
    inherit HttpMessageHandler()

    member val Respond: HttpRequestMessage -> string -> HttpResponseMessage =
        (fun _ _ -> new HttpResponseMessage(HttpStatusCode.NotFound)) with get, set

    member val Seen = ResizeArray<string * string * string>() with get

    override this.SendAsync(request, _) =
        task {
            let! body =
                if isNull request.Content then
                    Task.FromResult ""
                else
                    request.Content.ReadAsStringAsync()

            let auth =
                if isNull request.Headers.Authorization then
                    ""
                else
                    string request.Headers.Authorization

            lock this.Seen (fun () -> this.Seen.Add((string request.RequestUri, auth, body)))
            return this.Respond request body
        }

type Site =
    { App: WebApplication
      Server: TestServer
      Client: HttpClient
      Config: Config
      Root: string
      Capture: Capture
      Clock: ManualClock
      Github: FakeGithub }

    member s.Dispose() =
        s.Client.Dispose()
        s.App.DisposeAsync().AsTask().Wait()
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools()
        Directory.Delete(s.Root, true)

let private write (path: string) (text: string) =
    Directory.CreateDirectory(Path.GetDirectoryName path) |> ignore
    File.WriteAllText(path, text)

/// A page of ~2 KB, so compression has something to do.
let bulk = String.replicate 200 "marola 0123456789\n"

let secret = "TOP-SECRET-OUTSIDE-THE-ROOTS"

/// A made-up OAuth client secret: a test fails if it shows up in a log or a response.
let fakeClientSecret = "fake-client-secret-0123456789"

/// `root/static` (the page), `root/data` (the boards), `root/secret.txt` (outside both roots).
let startWith (tweak: Config -> Config) (customize: WebApplication -> unit) : Site =
    let root =
        Path.Combine(Path.GetTempPath(), "marola-tests-" + Guid.NewGuid().ToString "N")

    let static' = Path.Combine(root, "static")
    let data = Path.Combine(root, "data")
    write (Path.Combine(root, "secret.txt")) secret
    write (Path.Combine(root, "github-secret")) (fakeClientSecret + "\n")
    write (Path.Combine(static', "index.html")) ("<!doctype html><p>home</p>\n" + bulk)
    write (Path.Combine(static', "contact.html")) ("<!doctype html><form></form>\n" + bulk)
    write (Path.Combine(static', "404.html")) "<!doctype html><p>nada aqui</p>\n"
    write (Path.Combine(static', "en", "404.html")) "<!doctype html><p>nothing here</p>\n"
    write (Path.Combine(static', "app.js")) ("export const x = 1;\n" + bulk)
    write (Path.Combine(static', "app.1a2b3c4d5e.js")) "export const y = 2;\n"
    write (Path.Combine(static', "style.css")) ("body { margin: 0 }\n" + bulk)
    // The pages the server renders read the catalogs under `static/i18n`, as in app/dist.
    let rec repoRoot (dir: DirectoryInfo) =
        if Directory.Exists(Path.Combine(dir.FullName, "site", "i18n")) then
            dir.FullName
        else
            repoRoot dir.Parent

    for tag in [ "pt-BR"; "en" ] do
        write
            (Path.Combine(static', "i18n", tag + ".json"))
            (File.ReadAllText(
                Path.Combine(repoRoot (DirectoryInfo AppContext.BaseDirectory), "site", "i18n", tag + ".json")
            ))

    write (Path.Combine(static', "logo.svg")) ("<svg></svg>" + bulk)
    write (Path.Combine(static', "font.woff2")) bulk
    write (Path.Combine(static', "photo.png")) bulk
    write (Path.Combine(static', ".env")) secret
    write (Path.Combine(static', "sub", "x.txt")) "x"
    write (Path.Combine(static', "sub", ".hidden")) secret
    write (Path.Combine(static', ".well-known", "security.txt")) "Contact: https://example.org/report\n"
    write (Path.Combine(static', ".well-known", ".hidden")) secret
    write (Path.Combine(static', "sub", ".well-known", "security.txt")) secret
    write (Path.Combine(static', "data", "rio", "latest.json")) "{\"from\":\"static\"}"
    write (Path.Combine(static', "data", "floripa", "latest.json")) "{\"from\":\"static\"}"
    write (Path.Combine(data, "floripa", "latest.json")) "{\"from\":\"data\"}"

    let config =
        { Port = 0
          Static = static'
          Data = data
          Db = Path.Combine(root, "db", "marola.db")
          Studies = Path.Combine(root, "studies")
          StudiesQuota = 1_000_000L
          Dev = false
          GithubClientId = Some "test-client-id"
          GithubSecretFile = Some(Path.Combine(root, "github-secret"))
          GithubBase = "https://github.test"
          GithubApiBase = "https://api.github.test" }

    let config = tweak config
    let capture = new Capture()
    let github = new FakeGithub()
    let builder = App.createBuilder config
    builder.WebHost.UseTestServer() |> ignore
    builder.Logging.ClearProviders().AddProvider capture |> ignore
    builder.Services.AddSingleton<IStartupFilter, PeerFilter>() |> ignore

    builder.Services.AddSingleton<GithubHttp>(GithubHttp(new HttpClient(github)))
    |> ignore

    let clock = ManualClock(DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero))
    builder.Services.AddSingleton<TimeProvider>(clock) |> ignore
    let app = App.build builder config
    customize app
    app.StartAsync().Wait()

    { App = app
      Server = app.GetTestServer()
      Client = app.GetTestClient()
      Config = config
      Root = root
      Capture = capture
      Clock = clock
      Github = github }

let start (customize: WebApplication -> unit) : Site = startWith id customize

/// Runs `body` on a fresh site and cleans up.
let withSite (customize: WebApplication -> unit) (body: Site -> Task) : Task =
    task {
        let site = start customize

        try
            do! body site
        finally
            site.Dispose()
    }

/// Like `withSite`, with the config changed first (a test that has no GitHub login, for one).
let withSite' (tweak: Config -> Config) (body: Site -> Task) : Task =
    task {
        let site = startWith tweak ignore

        try
            do! body site
        finally
            site.Dispose()
    }

let plainSite (body: Site -> Task) = withSite ignore body

/// A request with a path as the pipeline sees it (already decoded), which `HttpClient` cannot send:
/// it normalises dots and slashes in a URI first.
let raw (site: Site) (meth: string) (path: string) : Task<HttpContext> =
    site.Server.SendAsync(fun ctx ->
        ctx.Request.Method <- meth
        ctx.Request.Path <- PathString path
        ctx.Request.Host <- HostString "localhost")

let bodyOf (ctx: HttpContext) : string =
    (new StreamReader(ctx.Response.Body)).ReadToEnd()

let form (pairs: (string * string) list) : HttpContent =
    new FormUrlEncodedContent(pairs |> List.map (fun (k, v) -> Collections.Generic.KeyValuePair(k, v)))

/// A POST of the contact form from the site's own page, as a browser sends it.
let post
    (site: Site)
    (peer: string)
    (origin: string option)
    (pairs: (string * string) list)
    : Task<HttpResponseMessage> =
    let request = new HttpRequestMessage(HttpMethod.Post, "/contact")
    request.Content <- form pairs
    origin |> Option.iter (fun o -> request.Headers.Add("Origin", o))

    if peer <> "" then
        request.Headers.Add("X-Test-Peer", peer)

    site.Client.SendAsync request

let goodForm =
    [ "email", "ana@example.org"
      "message", "A mensagem tem mais de dez caracteres."
      "website", "" ]

let header (response: HttpResponseMessage) (name: string) : string option =
    match response.Headers.TryGetValues name with
    | true, v -> Some(String.concat "," v)
    | _ ->
        match response.Content.Headers.TryGetValues name with
        | true, v -> Some(String.concat "," v)
        | _ -> None

/// The `name=value` pairs of the Set-Cookie headers, to send back as a `Cookie` header.
let cookies (response: HttpResponseMessage) : Map<string, string> =
    match response.Headers.TryGetValues "Set-Cookie" with
    | true, values ->
        values
        |> Seq.map (fun v ->
            let pair = v.Split(';').[0]
            let i = pair.IndexOf '='
            pair.Substring(0, i), pair.Substring(i + 1))
        |> Map.ofSeq
    | _ -> Map.empty

let setCookieHeader (response: HttpResponseMessage) (name: string) : string =
    response.Headers.GetValues "Set-Cookie"
    |> Seq.find (fun v -> v.StartsWith(name + "="))
