module Marola.Server.Program

open System
open System.Net
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Hosting
open Microsoft.AspNetCore.Server.Kestrel.Core

let private usage =
    "usage: marola-server            serve on 127.0.0.1:$MAROLA_PORT\n       marola-server inbox [--delete <id>]\n       marola-server studies ...   marola-server reports ...   (the board: see docs/6-board.md)\n       marola-server dev-account --login <name> --age-days <n>   (MAROLA_DEV=1, tests only)"

[<EntryPoint>]
let main argv =
    match Config.fromProcessEnv () with
    | Error message ->
        eprintfn "%s" message
        2
    | Ok config ->
        match List.ofArray argv with
        | "inbox" :: rest -> Inbox.run config rest Console.Out Console.Error
        | ("studies" | "reports") :: _ ->
            Board.run config DateTimeOffset.UtcNow (List.ofArray argv) Console.Out Console.Error
        | "dev-account" :: rest ->
            DevAccount.run
                config
                DateTimeOffset.UtcNow
                (Environment.GetEnvironmentVariable "MAROLA_DEV")
                rest
                Console.Out
                Console.Error
        | [] ->
            let builder = App.createBuilder config

            builder.WebHost.ConfigureKestrel(fun (o: KestrelServerOptions) ->
                o.AddServerHeader <- false
                // nginx faces the world; this port must never be reachable from outside.
                o.Listen(IPAddress.Loopback, config.Port)
                o.Limits.MaxRequestBodySize <- App.bodyLimit)
            |> ignore

            (App.build builder config).Run()
            0
        | _ ->
            eprintfn "%s" usage
            2
