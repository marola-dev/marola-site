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

        let path name fallback =
            Path.GetFullPath(defaultArg (get name |> Option.filter (String.IsNullOrWhiteSpace >> not)) fallback)

        port
        |> Result.map (fun p ->
            { Port = p
              Static = path "MAROLA_STATIC" "app/dist"
              Data = path "MAROLA_DATA" "data"
              Db = path "MAROLA_DB" "data/marola.db" })

    let fromProcessEnv () : Result<Config, string> =
        fromEnv (fun name ->
            match Environment.GetEnvironmentVariable name with
            | null -> None
            | value -> Some value)
