namespace Marola.Pages

open Marola
open Marola.Client

/// What the head of a page needs besides the language.
type PageHead =
    {
        /// The file name without `.html`: `about`, `contact-sent`.
        Slug: string
        Title: string
        Description: string
        /// `robots: noindex`.
        NoIndex: bool
        /// The canonical link, the language alternates and `og:url`. A 404 page answers any address,
        /// so it has none.
        Canonical: bool
        /// The slug of the nav link to mark as the current page.
        Current: string option
        /// A page the server renders at run time: its address has no `.html`, `/submit` and `/en/submit`.
        Dynamic: bool
    }

/// The frame of every static page: head, nav, header, footer and the language switch. The same chrome
/// as the map page, with plain links where the map page has buttons, and no script.
module Layout =

    let origin = "https://marola.dev"

    /// The path of a page: pt-BR at the root, English under `/en/`.
    let path (language: Language) (slug: string) : string =
        (match language with
         | Language.En -> "/en/"
         | Language.PtBr -> "/")
        + slug
        + ".html"

    /// The address of a page the server renders: no extension.
    let dynamicPath (language: Language) (slug: string) : string =
        (match language with
         | Language.En -> "/en/"
         | Language.PtBr -> "/")
        + slug

    let private where (page: PageHead) (language: Language) : string =
        if page.Dynamic then
            dynamicPath language page.Slug
        else
            path language page.Slug

    /// The map page, which the language param picks the language of.
    let mapPath (language: Language) : string =
        match language with
        | Language.En -> "/?lang=en"
        | Language.PtBr -> "/"

    let private ogLocale (language: Language) : string =
        match language with
        | Language.En -> "en_US"
        | Language.PtBr -> "pt_BR"

    let private meta (attrs: (string * string) list) : Node<unit> =
        Vdom.el "meta" (attrs |> List.map (fun (n, v) -> Vdom.attr n v)) []

    let private link (attrs: (string * string) list) : Node<unit> =
        Vdom.el "link" (attrs |> List.map (fun (n, v) -> Vdom.attr n v)) []

    let private headNodes (language: Language) (page: PageHead) : Node<unit> list =
        let other =
            if language = Language.En then
                Language.PtBr
            else
                Language.En

        let canonical =
            if page.Canonical then
                [ link [ "rel", "canonical"; "href", origin + where page language ]
                  link
                      [ "rel", "alternate"
                        "hreflang", Language.tag Language.PtBr
                        "href", origin + where page Language.PtBr ]
                  link
                      [ "rel", "alternate"
                        "hreflang", Language.tag Language.En
                        "href", origin + where page Language.En ]
                  link
                      [ "rel", "alternate"
                        "hreflang", "x-default"
                        "href", origin + where page Language.PtBr ] ]
            else
                []

        [ meta [ "charset", "utf-8" ]
          meta [ "name", "viewport"; "content", "width=device-width, initial-scale=1" ]
          Vdom.el "title" [] [ Vdom.text page.Title ]
          meta [ "name", "description"; "content", page.Description ]
          meta [ "name", "theme-color"; "content", "#ffffff" ] ]
        @ (if page.NoIndex then
               [ meta [ "name", "robots"; "content", "noindex" ] ]
           else
               [])
        @ canonical
        @ [ meta [ "property", "og:type"; "content", "website" ]
            meta [ "property", "og:site_name"; "content", "marola" ]
            meta [ "property", "og:title"; "content", page.Title ]
            meta [ "property", "og:description"; "content", page.Description ] ]
        @ (if page.Canonical then
               [ meta [ "property", "og:url"; "content", origin + where page language ] ]
           else
               [])
        @ [ meta [ "property", "og:locale"; "content", ogLocale language ]
            meta [ "property", "og:locale:alternate"; "content", ogLocale other ]
            meta [ "name", "twitter:card"; "content", "summary" ]
            link [ "rel", "icon"; "href", "/favicon.svg"; "type", "image/svg+xml" ]
            link [ "rel", "stylesheet"; "href", "/style.css" ] ]

    let private text (loc: Locale) (key: string) : string = I18n.t loc key []

    let private langLink (loc: Locale) (page: PageHead) (language: Language) (label: string) (name: string) =
        Vdom.el
            "a"
            [ Vdom.attr "href" (where page language)
              Vdom.attr "lang" (Language.tag language)
              Vdom.attr "hreflang" (Language.tag language)
              Vdom.attr "aria-label" name
              Vdom.attr "aria-current" (if loc.Language = language then "true" else "false") ]
            [ Vdom.text label ]

    let private languageSwitch (loc: Locale) (page: PageHead) : Node<unit> =
        Vdom.el
            "div"
            [ Vdom.cls "lang"
              Vdom.attr "role" "group"
              Vdom.attr "aria-label" (text loc "lang.label") ]
            [ NavView.svg
                  [ Vdom.cls "lang-icon"; Vdom.attr "viewBox" "0 0 16 16" ]
                  [ Vdom.svg "circle" [ Vdom.attr "cx" "8"; Vdom.attr "cy" "8"; Vdom.attr "r" "6.5" ] []
                    Vdom.svg
                        "ellipse"
                        [ Vdom.attr "cx" "8"
                          Vdom.attr "cy" "8"
                          Vdom.attr "rx" "2.8"
                          Vdom.attr "ry" "6.5" ]
                        []
                    Vdom.svg "path" [ Vdom.attr "d" "M1.5 8h13" ] [] ]
              langLink loc page Language.PtBr "PT-BR" "português (Brasil)"
              langLink loc page Language.En "EN" "English" ]

    /// The slugs the nav links to, in the order of the map page's nav. Every one is a page of this
    /// site, and the build checks that each has a file.
    let navSlugs = [ "news"; "about"; "contact"; "members"; "support" ]

    let private navLink (loc: Locale) (page: PageHead) (slug: string) (key: string) : Node<unit> =
        Vdom.el
            "a"
            ([ Vdom.attr "href" (path loc.Language slug) ]
             @ (if page.Current = Some slug then
                    [ Vdom.attr "aria-current" "page" ]
                else
                    []))
            [ Vdom.text (text loc key) ]

    let private external (loc: Locale) (url: string) (key: string) : Node<unit> =
        Vdom.el "a" [ Vdom.attr "href" url ] [ Vdom.text (text loc key) ]

    let private nav (loc: Locale) (page: PageHead) : Node<unit> =
        Vdom.el
            "nav"
            [ Vdom.cls "sitenav"; Vdom.attr "aria-label" (text loc "nav.label") ]
            [ external loc "https://docs.marola.dev/" "nav.docs"
              Vdom.el
                  "span"
                  [ Vdom.attr "aria-disabled" "true" ]
                  [ Vdom.el "span" [] [ Vdom.text (text loc "nav.alerts") ]
                    Vdom.text " "
                    Vdom.el "i" [] [ Vdom.text (text loc "nav.soon") ] ]
              navLink loc page "news" "nav.news"
              Vdom.el
                  "a"
                  ([ Vdom.attr "href" (dynamicPath loc.Language "studies") ]
                   @ (if page.Current = Some "studies" then
                          [ Vdom.attr "aria-current" "page" ]
                      else
                          []))
                  [ Vdom.text (text loc "nav.studies") ]
              navLink loc page "about" "nav.about"
              navLink loc page "contact" "nav.contact"
              external loc "https://github.com/marola-dev/marola-research/blob/main/README.md" "nav.research"
              external
                  loc
                  "https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf"
                  "nav.contribute"
              navLink loc page "members" "nav.members"
              navLink loc page "support" "nav.donate"
              languageSwitch loc page
              NavView.linkedin loc
              NavView.github loc ]

    let private header (loc: Locale) : Node<unit> =
        Vdom.el
            "header"
            [ Vdom.cls "bar" ]
            [ Vdom.el
                  "div"
                  [ Vdom.cls "brand" ]
                  [ Vdom.el "h1" [] [ Icons.icon "brand"; Vdom.text "marola" ]
                    Vdom.el "p" [ Vdom.cls "tagline" ] [ Vdom.text (text loc "header.tagline") ] ]
              Vdom.el
                  "div"
                  [ Vdom.cls "controls" ]
                  [ Vdom.el "a" [ Vdom.attr "href" (mapPath loc.Language) ] [ Vdom.text (text loc "about.back") ] ] ]

    /// The whole document for `main`, the children of `<main class="main about">`.
    let page (loc: Locale) (head: PageHead) (main: Node<unit> list) : string =
        let html =
            Vdom.el
                "html"
                [ Vdom.attr "lang" (Language.tag loc.Language) ]
                [ Vdom.el "head" [] (headNodes loc.Language head)
                  Vdom.el
                      "body"
                      []
                      [ nav loc head
                        header loc
                        Vdom.el "main" [ Vdom.cls "main about" ] main
                        Vdom.el
                            "footer"
                            [ Vdom.cls "footer" ]
                            [ Vdom.el "p" [] [ Vdom.text (text loc "footer.privacy") ]
                              Vdom.el
                                  "p"
                                  []
                                  [ Vdom.el
                                        "a"
                                        [ Vdom.attr "href" (dynamicPath loc.Language "submit") ]
                                        [ Vdom.text (text loc "footer.submit") ]
                                    Vdom.text " · "
                                    Vdom.el
                                        "a"
                                        [ Vdom.attr "href" (path loc.Language "privacy") ]
                                        [ Vdom.text (text loc "footer.privacy_page") ]
                                    Vdom.text " · "
                                    Vdom.el
                                        "a"
                                        [ Vdom.attr "href" (path loc.Language "takedown") ]
                                        [ Vdom.text (text loc "footer.takedown") ] ] ] ] ]

        "<!doctype html>\n" + Vdom.toHtml html + "\n"
