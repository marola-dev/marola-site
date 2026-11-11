namespace Marola.Server

open System
open System.IO

/// `marola-server inbox [--delete <id>]`: how the board reads the messages, over ssh.
module Inbox =

    let usage = "usage: marola-server inbox [--delete <id>]"

    let run (config: Config) (args: string list) (out: TextWriter) (err: TextWriter) : int =
        match args with
        | [] ->
            for m in Store.list config.Db do
                out.WriteLine $"#{m.Id}  {m.CreatedUtc}  {m.Email}"
                out.WriteLine m.Body
                out.WriteLine()

            0
        | [ "--delete"; id ] ->
            match Int64.TryParse id with
            | true, n when Store.delete config.Db n ->
                out.WriteLine $"deleted #{n}"
                0
            | true, n ->
                err.WriteLine $"no message #{n}"
                1
            | _ ->
                err.WriteLine usage
                2
        | _ ->
            err.WriteLine usage
            2
