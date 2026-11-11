module Marola.Pages.Build.Program

open System
open System.IO
open System.Net.Http
open Marola.Pages

let private usage = "usage: marola-pages-build <site-dir> <out-dir>"

// MEMBERS.md lives in marola-dev/.github. The repo keeps a copy at site/members/MEMBERS.md, and
// site/members.version names the commit it came from and its blob id, so a build needs no network.
// MEMBERS_SOURCE names another local copy and takes precedence. With neither file, the build fetches the commit.
let private membersText (site: string) : Result<string, string> =
    let local = Environment.GetEnvironmentVariable "MEMBERS_SOURCE"
    let version = File.ReadAllText(Path.Combine(site, "members.version"))
    let vendored = Path.Combine(site, "members", "MEMBERS.md")

    if not (String.IsNullOrEmpty local) then
        if File.Exists local then
            Ok(File.ReadAllText local)
        else
            Error("MEMBERS_SOURCE is not a file: " + local)
    elif File.Exists vendored then
        Members.vendored version (File.ReadAllBytes vendored)
    else
        let sha = (version.Split '\n' |> Array.head).Trim()

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
