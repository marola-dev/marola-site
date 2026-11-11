namespace Marola.Server

open System
open System.IO
open System.Text
open System.Threading.Tasks
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Http
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Logging
open Marola
open Marola.Pages
open Marola.Study

/// The human side of the study API: the pages, the forms and their POSTs. A POST needs the same site (Origin)
/// and, when it changes an account, a session and its CSRF token. The form of `/submit` goes through
/// `StudyApi.intake`, the same function as the API.
module Web =

    type State =
        { Config: Config
          Locale: Language -> Locale
          Key: byte[]
          Rates: StudyApi.KeyRates
          Log: ILogger }

    let private clock (ctx: HttpContext) =
        ctx.RequestServices.GetRequiredService<TimeProvider>().GetUtcNow()

    let private html (ctx: HttpContext) (status: int) (cache: string) (body: string) : Task<IResult> =
        ctx.Response.Headers.CacheControl <- cache
        Task.FromResult(Results.Content(body, "text/html; charset=utf-8", Encoding.UTF8, Nullable status))

    let private redirect (ctx: HttpContext) (location: string) : Task<IResult> =
        ctx.Response.Headers.CacheControl <- "no-store"
        ctx.Response.Headers.Location <- location
        Task.FromResult(Results.StatusCode 303)

    let private language (ctx: HttpContext) : Language =
        if ctx.Request.Path.StartsWithSegments(PathString "/en") then
            Language.En
        else
            Language.PtBr

    let private refuse (s: State) (ctx: HttpContext) (status: int) (pt: string * string) (en: string * string) =
        let loc = s.Locale(language ctx)
        let title, sentence = if loc.Language = Language.En then en else pt
        html ctx status "no-store" (Views.messagePage loc title sentence)

    let private forbidden s ctx =
        refuse
            s
            ctx
            403
            ("Pedido recusado",
             "O pedido não veio deste site ou a sessão do formulário venceu. Recarregue a página e tente de novo.")
            ("Request refused",
             "The request did not come from this site, or the form session ended. Reload the page and try again.")

    let private notFound s ctx =
        refuse
            s
            ctx
            404
            ("Não encontrado", "Não há nada neste endereço.")
            ("Not found", "There is nothing at this address.")

    let private sameSite (ctx: HttpContext) =
        let h (n: string) = ctx.Request.Headers[n].ToString()
        Contact.sameSite (h "Host") (h "Origin") (h "Referer")

    let private session (s: State) (ctx: HttpContext) =
        Session.current s.Config.Db s.Config.Dev (clock ctx) ctx

    let private toLogin (s: State) (ctx: HttpContext) : Task<IResult> =
        redirect ctx (Views.loginPath (s.Locale(language ctx)))

    /// The fields of a urlencoded POST, or `None` when the body is not a form or too big.
    let private readForm (ctx: HttpContext) : Task<Collections.Generic.IDictionary<string, string> option> =
        task {
            let ok =
                not (isNull ctx.Request.ContentType)
                && ctx.Request.ContentType.StartsWith(
                    "application/x-www-form-urlencoded",
                    StringComparison.OrdinalIgnoreCase
                )

            if not ok then
                return None
            else
                try
                    let! form = ctx.Request.ReadFormAsync()

                    return Some(form |> Seq.map (fun kv -> kv.Key, kv.Value.ToString()) |> dict)
                with
                | :? InvalidDataException
                | :? BadHttpRequestException -> return None
        }

    /// A POST that changes an account: same site, a session, a valid token. Anything else is refused.
    let private accountPost
        (s: State)
        (ctx: HttpContext)
        (act: Session.Live -> Collections.Generic.IDictionary<string, string> -> Task<IResult>)
        : Task<IResult> =
        task {
            if not (sameSite ctx) then
                return! forbidden s ctx
            else
                match session s ctx with
                | None -> return! toLogin s ctx
                | Some live ->
                    let! form = readForm ctx

                    match form with
                    | Some f when f.ContainsKey "csrf" && Session.csrfValid s.Key live.Hash f["csrf"] ->
                        return! act live f
                    | _ -> return! forbidden s ctx
        }

    let private accountView
        (s: State)
        (ctx: HttpContext)
        (live: Session.Live)
        (newKey: string option)
        (keyError: bool)
        : Task<IResult> =
        let loc = s.Locale(language ctx)
        let db = s.Config.Db

        html
            ctx
            200
            "no-store"
            (Views.accountPage
                loc
                live.Account
                (Session.csrfToken s.Key live.Hash)
                (StudyStore.listKeys db live.Account.GithubId)
                (StudyStore.listByAuthor db live.Account.GithubId)
                newKey
                keyError)

    // ---- handlers -------------------------------------------------------------------------------------

    let private submitGet (s: State) (ctx: HttpContext) : Task<IResult> =
        let loc = s.Locale(language ctx)

        let csrf =
            session s ctx |> Option.map (fun live -> Session.csrfToken s.Key live.Hash)

        html ctx 200 "no-store" (Views.submitPage loc csrf Map.empty [])

    let private submitPost (s: State) (ctx: HttpContext) : Task<IResult> =
        task {
            if not (sameSite ctx) then
                return! forbidden s ctx
            else
                match session s ctx with
                | None -> return! toLogin s ctx
                | Some live ->
                    let loc = s.Locale(language ctx)
                    let csrf = Session.csrfToken s.Key live.Hash

                    let! outcome, fields =
                        StudyApi.intake
                            s.Config
                            s.Rates
                            s.Log
                            ctx
                            live.Account
                            ("session:" + string live.Account.GithubId)
                            (set [ "csrf" ])
                            (fun f ->
                                match Map.tryFind "csrf" f with
                                | Some token -> Session.csrfValid s.Key live.Hash token
                                | None -> false)

                    match outcome with
                    | StudyApi.Created record -> return! redirect ctx (Views.url loc (urlOf record.Id))
                    | StudyApi.Failed f when f.Errors |> List.exists (fun e -> e.Code = "csrf") ->
                        return! forbidden s ctx
                    | StudyApi.Failed f ->
                        f.RetryAfter |> Option.iter (fun v -> ctx.Response.Headers.RetryAfter <- v)

                        // A duplicate shows the old study's link next to the error.
                        let errors =
                            match f.Existing with
                            | Some id ->
                                f.Errors
                                @ [ { Field = "id"
                                      Code = "duplicate"
                                      Message = urlOf id } ]
                            | None -> f.Errors

                        return! html ctx f.Status "no-store" (Views.submitPage loc (Some csrf) fields errors)
                    | StudyApi.DryRun _ -> return! html ctx 200 "no-store" (Views.submitPage loc (Some csrf) fields [])
        }

    let private studiesGet (s: State) (ctx: HttpContext) : Task<IResult> =
        let loc = s.Locale(language ctx)
        let q = ctx.Request.Query
        let area = parseArea (q["area"].ToString())
        let topic = parseTopic (q["topic"].ToString())

        let before =
            match q["before"].ToString() with
            | b when validId b -> Some b
            | _ -> None

        let limit = 20
        let studies = StudyStore.listStudies s.Config.Db area topic before limit

        let next =
            if List.length studies = limit then
                Some (List.last studies).Id
            else
                None

        html ctx 200 "public, max-age=60" (Views.studiesPage loc studies area topic next)

    let private studyOrPdf (s: State) (ctx: HttpContext) : Task<IResult> =
        task {
            let file = ctx.Request.RouteValues["file"].ToString()

            if file.EndsWith ".pdf" then
                do! StudyApi.pdf s.Config s.Log ctx file
                return Results.Empty
            else
                let record =
                    if validId file then
                        StudyStore.getStudy s.Config.Db file
                    else
                        None

                match record with
                | Some r -> return! html ctx 200 "public, max-age=60" (Views.studyPage (s.Locale(language ctx)) r)
                | None -> return! notFound s ctx
        }

    let private atom (s: State) (ctx: HttpContext) : Task<IResult> =
        let studies = StudyStore.listStudies s.Config.Db None None None 50
        ctx.Response.Headers.CacheControl <- "public, max-age=60"
        Task.FromResult(Results.Content(Views.atom studies, "application/atom+xml; charset=utf-8", Encoding.UTF8))

    let private accountGet (s: State) (ctx: HttpContext) : Task<IResult> =
        match session s ctx with
        | None -> toLogin s ctx
        | Some live -> accountView s ctx live None false

    let private createKey (s: State) (ctx: HttpContext) : Task<IResult> =
        accountPost s ctx (fun live _ ->
            match StudyStore.issueKey s.Config.Db (clock ctx) live.Account.GithubId with
            | Ok key -> accountView s ctx live (Some key) false
            | Error StudyStore.TooManyKeys -> accountView s ctx live None true)

    let private revokeKey (s: State) (ctx: HttpContext) : Task<IResult> =
        accountPost s ctx (fun live _ ->
            match Int64.TryParse(ctx.Request.RouteValues["id"].ToString()) with
            | true, id -> StudyStore.revokeKey s.Config.Db (clock ctx) live.Account.GithubId id |> ignore
            | _ -> ()

            redirect ctx (Views.url (s.Locale(language ctx)) "/account"))

    let private withdraw (s: State) (ctx: HttpContext) : Task<IResult> =
        accountPost s ctx (fun live _ ->
            let id = ctx.Request.RouteValues["id"].ToString()

            if validId id then
                StudyStore.withdraw s.Config.Db (clock ctx) live.Account.GithubId id |> ignore

            redirect ctx (Views.url (s.Locale(language ctx)) "/account"))

    let private logout (s: State) (ctx: HttpContext) : Task<IResult> =
        accountPost s ctx (fun live _ ->
            StudyStore.deleteSession s.Config.Db live.Token |> ignore
            Session.clear ctx s.Config.Dev (Session.sessionCookie s.Config.Dev)
            redirect ctx (if language ctx = Language.En then "/?lang=en" else "/"))

    let private reportGet (s: State) (ctx: HttpContext) : Task<IResult> =
        let id = ctx.Request.RouteValues["id"].ToString()

        if validId id && (StudyStore.getStudy s.Config.Db id).IsSome then
            html ctx 200 "no-store" (Views.reportPage (s.Locale(language ctx)) id false)
        else
            notFound s ctx

    let reasonCodes = Views.reasons |> List.map (fun (c, _, _) -> c)

    let private reportPost (s: State) (ctx: HttpContext) : Task<IResult> =
        task {
            let id = ctx.Request.RouteValues["id"].ToString()
            let loc = s.Locale(language ctx)

            if not (sameSite ctx) then
                return! forbidden s ctx
            else
                let! form = readForm ctx

                match form with
                | None -> return! forbidden s ctx
                | Some f ->
                    let field (n: string) = if f.ContainsKey n then f[n] else ""

                    if field "website" <> "" then
                        // The honeypot: a bot gets the thank-you page and nothing is stored.
                        return! html ctx 200 "no-store" (Views.thanksPage loc)
                    elif not (validId id) || (StudyStore.getStudy s.Config.Db id).IsNone then
                        return! notFound s ctx
                    else
                        let reason = Study.cleanText (field "reason")
                        let details = Study.cleanText (field "details")

                        let details =
                            if details.Length > 1000 then
                                details.Substring(0, 1000)
                            else
                                details

                        if not (List.contains reason reasonCodes) || (reason = "other" && details = "") then
                            return! html ctx 400 "no-store" (Views.reportPage loc id true)
                        else
                            let text = if details = "" then reason else reason + ": " + details
                            StudyStore.insertReport s.Config.Db (clock ctx) id text |> ignore
                            // The study id only: no address, no text.
                            s.Log.LogInformation("report stored {StudyId}", id)
                            return! html ctx 200 "no-store" (Views.thanksPage loc)
        }

    // ---- wiring ---------------------------------------------------------------------------------------

    let map (app: WebApplication) (config: Config) (logs: ILoggerFactory) : unit =
        let catalog =
            match Loader.catalog (Path.Combine(config.Static, "i18n")) with
            | Ok c -> c
            | Error e -> failwith ("the page catalogs are missing under MAROLA_STATIC/i18n: " + e)

        let s =
            { Config = config
              Locale =
                fun language ->
                    { Catalog = catalog
                      Language = language }
              Key = Session.loadKey config.Db
              Rates = StudyApi.KeyRates()
              Log = logs.CreateLogger "Marola.Web" }

        let get (pattern: string) (handler: State -> HttpContext -> Task<IResult>) =
            for prefix in [ ""; "/en" ] do
                app.MapGet(prefix + pattern, Func<HttpContext, Task<IResult>>(handler s))
                |> ignore

        let post (pattern: string) (strict: bool) (handler: State -> HttpContext -> Task<IResult>) =
            for prefix in [ ""; "/en" ] do
                let route =
                    app.MapPost(prefix + pattern, Func<HttpContext, Task<IResult>>(handler s))

                if strict then
                    route.RequireRateLimiting "strict" |> ignore

        get "/submit" submitGet
        post "/submit" false submitPost
        get "/studies" studiesGet
        get "/studies/{file}" studyOrPdf
        get "/account" accountGet
        post "/account/keys" false createKey
        post "/account/keys/{id}/revoke" false revokeKey
        post "/account/withdraw/{id}" false withdraw
        post "/logout" false logout
        get "/report/{id}" reportGet
        post "/report/{id}" true reportPost
        app.MapGet("/studies.atom", Func<HttpContext, Task<IResult>>(atom s)) |> ignore
