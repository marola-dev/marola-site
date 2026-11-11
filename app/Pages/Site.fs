namespace Marola.Pages

open Marola
open Marola.Client

/// What the pages are made of: the catalogs and the Markdown of every page, as read from disk.
type Env =
    {
        Catalog: Catalog
        /// `<slug>.<language tag>` to the file's text.
        Content: Map<string, string>
    }

/// The pages. One page is a function from a language to its HTML text.
module Site =

    /// Every page, by file name without `.html`.
    let slugs = [ "about"; "support"; "contact"; "contact-sent"; "404" ]

    let contentKey (slug: string) (language: Language) : string = slug + "." + Language.tag language

    /// Where a page is written, from the output folder: pt-BR at the root, English under `en/`.
    let file (language: Language) (slug: string) : string =
        (Layout.path language slug).TrimStart '/'

    // The form posts to the same path the page is under, so the server can answer in the visitor's language.
    let private form (loc: Locale) : Node<unit> =
        let text key = I18n.t loc key []

        let field (key: string) (control: Node<unit>) =
            Vdom.el "label" [] [ Vdom.el "span" [] [ Vdom.text (text key) ]; Vdom.text " "; control ]

        Vdom.el
            "div"
            [ Vdom.cls "about-body" ]
            [ Vdom.el
                  "form"
                  [ Vdom.cls "contact"
                    Vdom.attr
                        "action"
                        (if loc.Language = Language.En then
                             "/en/contact"
                         else
                             "/contact")
                    Vdom.attr "method" "POST" ]
                  [ // The honeypot: a person never sees it, the server drops a post that fills it.
                    Vdom.el
                        "input"
                        ([ Vdom.attr "type" "text"
                           Vdom.attr "name" "website"
                           Vdom.attr "tabindex" "-1"
                           Vdom.attr "autocomplete" "off"
                           Vdom.attr "aria-hidden" "true" ]
                         @ Vdom.hidden true)
                        []
                    field
                        "contact.name"
                        (Vdom.el
                            "input"
                            [ Vdom.attr "type" "text"
                              Vdom.attr "name" "name"
                              Vdom.attr "required" ""
                              Vdom.attr "autocomplete" "name" ]
                            [])
                    field
                        "contact.email"
                        (Vdom.el
                            "input"
                            [ Vdom.attr "type" "email"
                              Vdom.attr "name" "email"
                              Vdom.attr "required" ""
                              Vdom.attr "autocomplete" "email" ]
                            [])
                    field
                        "contact.message"
                        (Vdom.el
                            "textarea"
                            [ Vdom.attr "name" "message"; Vdom.attr "rows" "6"; Vdom.attr "required" "" ]
                            [])
                    Vdom.el "button" [ Vdom.attr "type" "submit" ] [ Vdom.text (text "contact.send") ] ] ]

    // How each page differs from plain prose: its nav mark, whether a search engine may list it, its extras.
    let private head (slug: string) (doc: Doc) : PageHead =
        { Slug = slug
          Title = doc.Title
          Description = doc.Description
          NoIndex = slug = "contact" || slug = "contact-sent" || slug = "404"
          Canonical = slug <> "404"
          Current =
            match slug with
            | "contact"
            | "contact-sent" -> Some "contact"
            | "404" -> None
            | other -> Some other }

    /// One page in one language, or why it cannot be made.
    let render (env: Env) (slug: string) (language: Language) : Result<string, string> =
        let loc =
            { Catalog = env.Catalog
              Language = language }

        match Map.tryFind (contentKey slug language) env.Content with
        | None -> Error("no content for " + contentKey slug language)
        | Some text ->
            Markdown.parse text
            |> Result.mapError (fun e -> contentKey slug language + ": " + e)
            |> Result.map (fun doc ->
                let article =
                    Vdom.el "article" [ Vdom.cls "about-body"; Vdom.attr "lang" (Language.tag language) ] doc.Body

                Layout.page loc (head slug doc) (article :: (if slug = "contact" then [ form loc ] else [])))

    /// Every page in every language: the path from the output folder and the text to write there.
    let all (env: Env) : Result<(string * string) list, string> =
        [ for slug in slugs do
              for language in Language.all do
                  yield render env slug language |> Result.map (fun html -> file language slug, html) ]
        |> List.fold
            (fun acc item ->
                match acc, item with
                | Ok xs, Ok x -> Ok(x :: xs)
                | Error e, _
                | _, Error e -> Error e)
            (Ok [])
        |> Result.map List.rev
