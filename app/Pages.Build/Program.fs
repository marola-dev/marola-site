module Marola.Pages.Build.Program

open System
open System.IO
open Marola.Pages

let private usage = "usage: marola-pages-build <content-dir> <i18n-dir> <out-dir>"

[<EntryPoint>]
let main argv =
    match argv with
    | [| contentDir; i18nDir; outDir |] ->
        match Loader.load contentDir i18nDir |> Result.bind Site.all with
        | Error message ->
            eprintfn "pages: %s" message
            1
        | Ok pages ->
            for (file, html) in pages do
                let target = Path.Combine(outDir, file)
                Directory.CreateDirectory(Path.GetDirectoryName target) |> ignore
                File.WriteAllText(target, html)

            printfn "pages: %d files in %s" (List.length pages) outDir
            0
    | _ ->
        eprintfn "%s" usage
        2
