/// The files the tests read: the repository's own catalogs and page Markdown.
module Marola.Pages.Tests.Support

open System
open System.IO
open Marola
open Marola.Pages

/// The nearest folder above the build output that holds the page content.
let root =
    let rec up (dir: DirectoryInfo) =
        if Directory.Exists(Path.Combine(dir.FullName, "site", "content", "pages")) then
            dir.FullName
        elif isNull dir.Parent then
            failwith "repository root not found"
        else
            up dir.Parent

    up (DirectoryInfo AppContext.BaseDirectory)

let env: Env =
    match Loader.load (Path.Combine(root, "site/content/pages")) (Path.Combine(root, "site/i18n")) with
    | Ok env -> env
    | Error message -> failwith message

let render (slug: string) (language: Language) : string =
    match Site.render env slug language with
    | Ok html -> html
    | Error message -> failwith message
