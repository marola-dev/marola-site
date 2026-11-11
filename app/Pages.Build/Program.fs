module Marola.Pages.Build.Program

open System
open System.IO
open System.Net.Http
open Marola.Pages

let private usage = "usage: marola-pages-build <site-dir> <out-dir>"

// MEMBERS.md lives in marola-dev/.github, not here: the repo keeps only the commit it was built from
// (site/members.version). MEMBERS_SOURCE names a local copy, for a build with no network.
let private membersText (site: string) : Result<string, string> =
    let local = Environment.GetEnvironmentVariable "MEMBERS_SOURCE"

    if not (String.IsNullOrEmpty local) then
        if File.Exists local then
            Ok(File.ReadAllText local)
        else
            Error("MEMBERS_SOURCE is not a file: " + local)
    else
        let sha = File.ReadAllText(Path.Combine(site, "members.version")).Trim()

        let url =
            "https://raw.githubusercontent.com/marola-dev/.github/" + sha + "/MEMBERS.md"

        try
            use client = new HttpClient(Timeout = TimeSpan.FromSeconds 30.0)
            Ok(client.GetStringAsync(url).Result)
        with e ->
            Error(
                "cannot fetch "
                + url
                + " (set MEMBERS_SOURCE to a local MEMBERS.md): "
                + e.GetBaseException().Message
            )

[<EntryPoint>]
let main argv =
    match argv with
    | [| site; outDir |] ->
        let built =
            membersText site
            |> Result.bind (Loader.load site)
            |> Result.bind (fun env ->
                Site.all env
                |> Result.bind (fun pages ->
                    Meta.files env (DateOnly.FromDateTime DateTime.UtcNow)
                    |> Result.map (fun files -> pages @ files)))

        match built with
        | Error message ->
            eprintfn "pages: %s" message
            1
        | Ok pages ->
            for (file, text) in pages do
                let target = Path.Combine(outDir, file)
                Directory.CreateDirectory(Path.GetDirectoryName target) |> ignore
                File.WriteAllText(target, text)

            printfn "pages: %d files in %s" (List.length pages) outDir
            0
    | _ ->
        eprintfn "%s" usage
        2
