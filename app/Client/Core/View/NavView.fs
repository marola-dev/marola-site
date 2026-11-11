module Marola.Client.NavView

open Marola

let private link (model: Model) (url: string) (key: string) : Node<Msg> =
    Vdom.el "a" [ Vdom.attr "href" url ] [ Vdom.text (Words.t model key) ]

let private langButton (model: Model) (language: Language) (label: string) (name: string) : Node<Msg> =
    Vdom.el
        "button"
        [ Vdom.attr "type" "button"
          Vdom.attr "lang" (Language.tag language)
          Vdom.attr "aria-label" name
          Words.pressed (model.Loc.Language = language)
          Vdom.onClick (LanguagePicked language) ]
        [ Vdom.text label ]

/// An inline decorative svg: hidden from assistive technology, not focusable.
let svg (attrs: Attr<'msg> list) (children: Node<'msg> list) : Node<'msg> =
    Vdom.svg "svg" (Vdom.attr "aria-hidden" "true" :: Vdom.attr "focusable" "false" :: attrs) children

let private languageToggle (model: Model) : Node<Msg> =
    Vdom.el
        "div"
        [ Vdom.elId "lang"
          Vdom.cls "lang"
          Vdom.attr "role" "group"
          Vdom.attr "aria-label" (Words.t model "lang.label") ]
        [ svg
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
          langButton model Language.PtBr "PT-BR" "português (Brasil)"
          langButton model Language.En "EN" "English" ]

let linkedin (loc: Locale) : Node<'msg> =
    Vdom.el
        "a"
        [ Vdom.cls "li"
          Vdom.attr "href" "https://www.linkedin.com/company/marola-dev/"
          Vdom.attr "target" "_blank"
          Vdom.attr "rel" "noopener"
          Vdom.attr "aria-label" (I18n.t loc "li.label" [])
          Vdom.attr "title" (I18n.t loc "li.label" []) ]
        [ svg
              [ Vdom.cls "li-mark"; Vdom.attr "viewBox" "0 0 24 24" ]
              [ Vdom.svg "path" [ Vdom.attr "d" "M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-4 0v7h-4v-7a6 6 0 0 1 6-6z" ] []
                Vdom.svg
                    "rect"
                    [ Vdom.attr "x" "2"
                      Vdom.attr "y" "9"
                      Vdom.attr "width" "4"
                      Vdom.attr "height" "12" ]
                    []
                Vdom.svg "circle" [ Vdom.attr "cx" "4"; Vdom.attr "cy" "4"; Vdom.attr "r" "2" ] [] ]
          Vdom.el "span" [ Vdom.cls "li-name" ] [ Vdom.text (I18n.t loc "li.name" []) ] ]

let private githubMark =
    "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.06-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"

let github (loc: Locale) : Node<'msg> =
    Vdom.el
        "a"
        [ Vdom.cls "gh"
          Vdom.attr "href" "https://github.com/marola-dev/marola"
          Vdom.attr "aria-label" (I18n.t loc "gh.label" [])
          Vdom.attr "title" (I18n.t loc "gh.title" []) ]
        [ svg
              [ Vdom.cls "gh-mark"; Vdom.attr "viewBox" "0 0 16 16" ]
              [ Vdom.svg "path" [ Vdom.attr "fill" "currentColor"; Vdom.attr "d" githubMark ] [] ]
          Vdom.el
              "span"
              [ Vdom.cls "gh-name" ]
              [ Vdom.el "span" [ Vdom.cls "gh-owner" ] [ Vdom.text "marola-dev/" ]
                Vdom.text "marola" ]
          Vdom.el
              "span"
              [ Vdom.cls "gh-star" ]
              [ svg
                    [ Vdom.attr "viewBox" "0 0 16 16" ]
                    [ Vdom.svg
                          "path"
                          [ Vdom.attr "d" "M8 1.6l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.4l-3.8 2 .7-4.3-3.1-3 4.3-.6z" ]
                          [] ]
                Vdom.el "span" [] [ Vdom.text (I18n.t loc "gh.star" []) ] ] ]

let view (model: Model) : Node<Msg> list =
    [ Vdom.el
          "nav"
          [ Vdom.cls "sitenav"; Vdom.attr "aria-label" (Words.t model "nav.label") ]
          [ link model "https://docs.marola.dev/" "nav.docs"
            Vdom.el
                "span"
                [ Vdom.attr "aria-disabled" "true" ]
                [ Vdom.el "span" [] [ Vdom.text (Words.t model "nav.alerts") ]
                  Vdom.text " "
                  Vdom.el "i" [] [ Vdom.text (Words.t model "nav.soon") ] ]
            link model "news.html" "nav.news"
            link model "/studies" "nav.studies"
            link model "about.html" "nav.about"
            link model "contact.html" "nav.contact"
            link model "https://github.com/marola-dev/marola-research/blob/main/README.md" "nav.research"
            link model "https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf" "nav.contribute"
            link model "members.html" "nav.members"
            link model "support.html" "nav.donate"
            languageToggle model
            linkedin model.Loc
            github model.Loc ] ]
