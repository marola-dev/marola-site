namespace Marola.Pages

open System.IO
open Marola
open Thoth.Json.Newtonsoft

/// Reads the catalogs and the page Markdown from disk.
module Loader =

    let catalog (i18nDir: string) : Result<Catalog, string> =
        Language.all
        |> List.fold
            (fun acc language ->
                acc
                |> Result.bind (fun map ->
                    Decode.fromString
                        I18n.messagesDecoder
                        (File.ReadAllText(Path.Combine(i18nDir, Language.tag language + ".json")))
                    |> Result.map (fun messages -> Map.add language messages map)
                    |> Result.mapError (fun e -> Language.tag language + ".json: " + e)))
            (Ok Map.empty)

    /// `site` is the `site/` folder: `content/pages` holds `<slug>.<tag>.md` for every page and language,
    /// `content/news` the posts, `i18n` the catalogs.
    let load (site: string) (members: string) : Result<Env, string> =
        let pages = Path.Combine(site, "content", "pages")
        let news = Path.Combine(site, "content", "news")
        let avatars = Path.Combine(site, "static", "img", "members")

        let files =
            [ for slug in Site.allSlugs do
                  for language in Language.all do
                      let key = Site.contentKey slug language
                      let path = Path.Combine(pages, key + ".md")

                      if File.Exists path then
                          yield key, File.ReadAllText path ]

        let posts =
            [ for path in Directory.GetFiles(news, "*.md") |> Array.sort do
                  if Path.GetFileName path <> "README.md" then
                      yield Path.GetFileName path, File.ReadAllText path ]

        let index = Path.Combine(news, "README.md")

        let areas =
            Decode.fromString Area.listDecoder (File.ReadAllText(Path.Combine(site, "areas.json")))
            |> Result.mapError (fun e -> "areas.json: " + e)

        catalog (Path.Combine(site, "i18n"))
        |> Result.bind (fun catalog ->
            areas
            |> Result.map (fun areas ->
                { Catalog = catalog
                  Content = Map.ofList files
                  News = posts
                  NewsIndex = if File.Exists index then File.ReadAllText index else ""
                  Members = members
                  Areas = areas
                  Avatars =
                    if Directory.Exists avatars then
                        Directory.GetFiles avatars
                        |> Array.map (fun p -> Path.GetFileNameWithoutExtension p, Path.GetFileName p)
                        |> Map.ofArray
                    else
                        Map.empty }))
