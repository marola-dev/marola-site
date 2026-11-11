namespace Marola.Server

open System
open System.IO
open System.Security.Cryptography
open System.Text

/// `marola-server dev-account --login <name> --age-days <n>`: an account and an API key for the smoke test.
/// Real accounts come from the GitHub login. It refuses unless MAROLA_DEV=1, so it cannot mint a key by mistake.
module DevAccount =

    let usage =
        "usage: marola-server dev-account --login <name> --age-days <n>   (needs MAROLA_DEV=1)"

    /// The same login gives the same id, so a second run reuses the account. Positive, below 2^62.
    let private idOf (login: string) : int64 =
        BitConverter.ToInt64(SHA256.HashData(Encoding.UTF8.GetBytes login), 0)
        &&& 0x3fff_ffff_ffff_ffffL

    let run
        (config: Config)
        (now: DateTimeOffset)
        (dev: string)
        (args: string list)
        (out: TextWriter)
        (err: TextWriter)
        : int =
        if dev <> "1" then
            err.WriteLine "dev-account is for tests: set MAROLA_DEV=1"
            1
        else
            match args with
            | [ "--login"; login; "--age-days"; days ] when login <> "" ->
                match Int32.TryParse days with
                | true, n when n >= 0 && n <= 36500 ->
                    Store.init config.Db
                    StudyStore.migrate config.Db
                    let id = idOf login

                    StudyStore.upsertAccount
                        config.Db
                        now
                        { GithubId = id
                          Login = login
                          CreatedGithubUtc = StudyStore.utc (now.AddDays(float -n)) }

                    match StudyStore.issueKey config.Db now id with
                    | Ok key ->
                        out.WriteLine key
                        0
                    | Error StudyStore.TooManyKeys ->
                        err.WriteLine "the account already has 3 active keys"
                        1
                | _ ->
                    err.WriteLine usage
                    2
            | _ ->
                err.WriteLine usage
                2
