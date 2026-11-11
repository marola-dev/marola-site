namespace Marola.Pages

open System.IO
open Marola
open Thoth.Json.Newtonsoft

/// Reads the catalogs and the page Markdown from disk.
module Loader =

    let private catalog (i18nDir: string) : Result<Catalog, string> =
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

    /// `i18nDir` holds `<tag>.json`, `contentDir` holds `<slug>.<tag>.md` for every page and language.
    let load (contentDir: string) (i18nDir: string) : Result<Env, string> =
        let files =
            [ for slug in Site.slugs do
                  for language in Language.all do
                      let key = Site.contentKey slug language
                      let path = Path.Combine(contentDir, key + ".md")

                      if File.Exists path then
                          yield key, File.ReadAllText path ]

        catalog i18nDir
        |> Result.map (fun catalog ->
            { Catalog = catalog
              Content = Map.ofList files })
