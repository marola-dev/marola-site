namespace Marola.Server

open System
open System.IO
open System.Net.Http
open System.Net.Http.Headers
open System.Security.Cryptography
open System.Text
open System.Text.Json
open System.Text.RegularExpressions
open System.Threading.Tasks
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Http
open Microsoft.Extensions.Logging

/// The client of the two GitHub calls. A service of its own so a test swaps in a fake GitHub.
type GithubHttp(client: HttpClient) =
    member _.Client = client

/// Login with GitHub, the web flow with an empty scope: the only data read is the public profile (id,
/// login, creation date). The access token lives in a local variable of one request and is dropped.
module GithubLogin =

    let loginPath = "/auth/github/login"
    let callbackPath = "/auth/github/callback"

    let newClient () : HttpClient =
        new HttpClient(Timeout = TimeSpan.FromSeconds 10., MaxResponseContentBufferSize = 65_536L)

    /// The client id and the secret, or `None`. The secret is read from its file at each use and never held.
    let private secret (config: Config) : (string * string) option =
        match config.GithubClientId, config.GithubSecretFile with
        | Some id, Some file when File.Exists file ->
            match File.ReadAllText(file).Trim() with
            | "" -> None
            | s -> Some(id, s)
        | _ -> None

    let private noStore (ctx: HttpContext) =
        ctx.Response.Headers.CacheControl <- "no-store"

    /// A plain answer with no text from GitHub and no detail of what failed.
    let private page (status: int) (text: string) : IResult =
        Results.Text(text + "\n", "text/plain; charset=utf-8", Encoding.UTF8, Nullable status)

    let private loginShape =
        Regex(@"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", RegexOptions.Compiled)

    let login (config: Config) (ctx: HttpContext) : IResult =
        noStore ctx

        match secret config with
        | None -> page 503 "login is not configured"
        | Some(clientId, _) ->
            let state =
                Convert.ToHexString(RandomNumberGenerator.GetBytes 16).ToLowerInvariant()

            let lang =
                if ctx.Request.Query["lang"].ToString() = "en" then
                    "en"
                else
                    "pt"

            Session.set ctx config.Dev (Session.stateCookie config.Dev) (state + "." + lang) (TimeSpan.FromMinutes 10.)

            // GitHub uses the callback registered with the app. Dev mode names it, for a fake GitHub that has none.
            let redirect =
                if config.Dev then
                    "&redirect_uri="
                    + Uri.EscapeDataString("http://" + ctx.Request.Host.Value + callbackPath)
                else
                    ""

            // No `scope`: an empty scope reads public data only.
            Results.Redirect(
                config.GithubBase
                + "/login/oauth/authorize?client_id="
                + Uri.EscapeDataString clientId
                + "&state="
                + state
                + redirect
            )

    type private Profile =
        { Id: int64
          Login: string
          Created: string }

    let private json (response: HttpResponseMessage) : Task<JsonDocument option> =
        task {
            if not response.IsSuccessStatusCode then
                return None
            else
                let! text = response.Content.ReadAsStringAsync()

                try
                    return Some(JsonDocument.Parse text)
                with :? JsonException ->
                    return None
        }

    let private str (doc: JsonDocument) (name: string) : string option =
        match doc.RootElement.ValueKind, doc.RootElement.TryGetProperty name with
        | JsonValueKind.Object, (true, v) when v.ValueKind = JsonValueKind.String -> Some(v.GetString())
        | _ -> None

    /// The code for the profile. The token is a local of this function and goes out of scope with it.
    let private fetchProfile
        (config: Config)
        (http: HttpClient)
        (clientId: string)
        (clientSecret: string)
        (code: string)
        =
        task {
            use tokenRequest =
                new HttpRequestMessage(HttpMethod.Post, config.GithubBase + "/login/oauth/access_token")

            tokenRequest.Headers.Accept.Add(MediaTypeWithQualityHeaderValue "application/json")
            tokenRequest.Headers.UserAgent.ParseAdd "marola-site"

            tokenRequest.Content <-
                new FormUrlEncodedContent(
                    [ Collections.Generic.KeyValuePair("client_id", clientId)
                      Collections.Generic.KeyValuePair("client_secret", clientSecret)
                      Collections.Generic.KeyValuePair("code", code) ]
                )

            use! tokenResponse = http.SendAsync tokenRequest
            let! tokenDoc = json tokenResponse

            match tokenDoc |> Option.bind (fun d -> str d "access_token") with
            | None -> return None
            | Some token ->
                use userRequest =
                    new HttpRequestMessage(HttpMethod.Get, config.GithubApiBase + "/user")

                userRequest.Headers.Authorization <- AuthenticationHeaderValue("Bearer", token)
                userRequest.Headers.Accept.Add(MediaTypeWithQualityHeaderValue "application/vnd.github+json")
                userRequest.Headers.UserAgent.ParseAdd "marola-site"
                use! userResponse = http.SendAsync userRequest
                let! user = json userResponse

                match user with
                | None -> return None
                | Some doc ->
                    use _ = doc

                    let id =
                        match doc.RootElement.TryGetProperty "id" with
                        | true, v when v.ValueKind = JsonValueKind.Number ->
                            match v.TryGetInt64() with
                            | true, n when n > 0L -> Some n
                            | _ -> None
                        | _ -> None

                    let created =
                        str doc "created_at"
                        |> Option.bind (fun s ->
                            match DateTimeOffset.TryParse s with
                            | true, t -> Some(StudyStore.utc t)
                            | _ -> None)

                    match id, str doc "login" |> Option.filter loginShape.IsMatch, created with
                    | Some id, Some login, Some created ->
                        return
                            Some
                                { Id = id
                                  Login = login
                                  Created = created }
                    | _ -> return None
        }

    let callback (config: Config) (log: ILogger) (ctx: HttpContext) : Task<IResult> =
        task {
            noStore ctx
            let dev = config.Dev
            let stateName = Session.stateCookie dev
            let cookie = ctx.Request.Cookies[stateName]
            // The state is single-use: a replayed callback finds no cookie.
            Session.clear ctx dev stateName

            let state, lang =
                match cookie with
                | null -> "", "pt"
                | c ->
                    match c.LastIndexOf '.' with
                    | -1 -> "", "pt"
                    | i -> c.Substring(0, i), (if c.Substring(i + 1) = "en" then "en" else "pt")

            let q = ctx.Request.Query
            let code = q["code"].ToString()

            match secret config with
            | None -> return page 503 "login is not configured"
            | Some(clientId, clientSecret) ->
                if
                    state.Length = 0
                    || not (Session.safeEquals state (q["state"].ToString()))
                    || code = ""
                    || code.Length > 200
                then
                    return page 400 "login failed: start again from the site"
                else
                    let http = ctx.RequestServices.GetService(typeof<GithubHttp>) :?> GithubHttp

                    let! profile =
                        task {
                            try
                                return! fetchProfile config http.Client clientId clientSecret code
                            with e ->
                                // The type only: a message could carry a URL, and nothing here may carry a token.
                                log.LogWarning("github login failed {Reason}", e.GetType().Name)
                                return None
                        }

                    match profile with
                    | None -> return page 502 "login failed: GitHub did not confirm the login"
                    | Some p ->
                        let now = ctx.RequestServices.GetService(typeof<TimeProvider>) :?> TimeProvider
                        let now = now.GetUtcNow()

                        StudyStore.upsertAccount
                            config.Db
                            now
                            { GithubId = p.Id
                              Login = p.Login
                              CreatedGithubUtc = p.Created }

                        let token = StudyStore.createSession config.Db now p.Id
                        Session.set ctx dev (Session.sessionCookie dev) token StudyStore.sessionLifetime
                        log.LogInformation("login {AccountId}", p.Id)
                        ctx.Response.Headers.Location <- (if lang = "en" then "/en/account" else "/account")
                        return Results.StatusCode 303
        }

    let map (app: WebApplication) (config: Config) (logs: ILoggerFactory) : unit =
        let log = logs.CreateLogger "Marola.Login"

        app.MapGet(loginPath, Func<HttpContext, IResult>(login config)).RequireRateLimiting("strict")
        |> ignore

        app.MapGet(callbackPath, Func<HttpContext, Task<IResult>>(callback config log)).RequireRateLimiting("strict")
        |> ignore
