namespace Marola.Server

open System
open System.IO

/// Where the server listens and what it reads and writes. All paths are absolute after `fromEnv`.
type Config =
    {
        Port: int
        /// The built page (`app/dist`): served at `/`.
        Static: string
        /// The board data folder: `/data/<x>` is looked up here first, then under `Static`.
        Data: string
        /// The SQLite file of the contact messages.
        Db: string
        /// Where the PDFs of the studies live, as `<sha256>.pdf`. Outside `Static`, never served as a file tree.
        Studies: string
        /// The most bytes the PDFs may take in all.
        StudiesQuota: int64
        /// `MAROLA_DEV=1`: cookies without `Secure` and the `__Host-` prefix, and the GitHub URLs may be overridden.
        /// For the smoke script on plain HTTP and a fake GitHub; never set in production.
        Dev: bool
        /// The OAuth app's client id (public). Without it and the secret file, login answers 503.
        GithubClientId: string option
        /// A path to the file that holds the OAuth client secret. The secret itself is never in the environment.
        GithubSecretFile: string option
        GithubBase: string
        GithubApiBase: string
    }

module Config =

    /// Reads the MAROLA_* variables through `get`, so a test passes a map and not the process environment.
    let fromEnv (get: string -> string option) : Result<Config, string> =
        let port =
            match get "MAROLA_PORT" with
            | None -> Ok 8080
            | Some text ->
                match Int32.TryParse text with
                | true, p when p >= 1 && p <= 65535 -> Ok p
                | _ -> Error("MAROLA_PORT is not a port number: " + text)

        let quota =
            match get "MAROLA_STUDIES_QUOTA" with
            | None -> Ok(2L * 1024L * 1024L * 1024L)
            | Some text ->
                match Int64.TryParse text with
                | true, n when n >= 1L -> Ok n
                | _ -> Error("MAROLA_STUDIES_QUOTA is not a number of bytes: " + text)

        let nonEmpty name =
            get name |> Option.filter (String.IsNullOrWhiteSpace >> not)

        let path name fallback =
            Path.GetFullPath(defaultArg (nonEmpty name) fallback)

        let dev = get "MAROLA_DEV" = Some "1"

        // A URL override only counts in dev mode: in production the OAuth code and secret go to github.com.
        let url name fallback =
            if dev then
                defaultArg (nonEmpty name) fallback
            else
                fallback

        Result.bind (fun p -> quota |> Result.map (fun q -> p, q)) port
        |> Result.map (fun (p, quota) ->
            { Port = p
              Static = path "MAROLA_STATIC" "app/dist"
              Data = path "MAROLA_DATA" "data"
              Db = path "MAROLA_DB" "data/marola.db"
              Studies = path "MAROLA_STUDIES" "data/studies"
              StudiesQuota = quota
              Dev = dev
              GithubClientId = nonEmpty "MAROLA_GITHUB_CLIENT_ID"
              GithubSecretFile = nonEmpty "MAROLA_GITHUB_CLIENT_SECRET_FILE" |> Option.map Path.GetFullPath
              GithubBase = url "MAROLA_GITHUB_BASE" "https://github.com"
              GithubApiBase = url "MAROLA_GITHUB_API_BASE" "https://api.github.com" })

    let fromProcessEnv () : Result<Config, string> =
        fromEnv (fun name ->
            match Environment.GetEnvironmentVariable name with
            | null -> None
            | value -> Some value)
