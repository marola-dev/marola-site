module View.Nav exposing (github, linkedin, svgIcon, view)

import Html exposing (Html)
import I18n exposing (Locale)
import Language exposing (Language(..))
import Model exposing (Model)
import Msg exposing (Msg(..))
import Svg
import Ui exposing (attr, cls, idAttr)
import Words


link : Model -> String -> String -> Html Msg
link model url key =
    Html.a [ attr "href" url ] [ Html.text (Words.t model key) ]


langButton : Model -> Language -> String -> String -> Html Msg
langButton model language label name =
    Html.button
        [ attr "type" "button"
        , attr "lang" (Language.tag language)
        , attr "aria-label" name
        , Words.pressed (model.loc.language == language)
        , Ui.onClick (LanguagePicked language)
        ]
        [ Html.text label ]


{-| An inline decorative svg: hidden from assistive technology, not focusable.
-}
svgIcon : List (Html.Attribute msg) -> List (Html msg) -> Html msg
svgIcon attrs children =
    Svg.svg (attr "aria-hidden" "true" :: attr "focusable" "false" :: attrs) children


shape : String -> List ( String, String ) -> Html msg
shape tag attrs =
    Svg.node tag (List.map (\( k, v ) -> attr k v) attrs) []


languageToggle : Model -> Html Msg
languageToggle model =
    Html.div
        [ idAttr "lang", cls "lang", attr "role" "group", attr "aria-label" (Words.t model "lang.label") ]
        [ svgIcon [ cls "lang-icon", attr "viewBox" "0 0 16 16" ]
            [ shape "circle" [ ( "cx", "8" ), ( "cy", "8" ), ( "r", "6.5" ) ]
            , shape "ellipse" [ ( "cx", "8" ), ( "cy", "8" ), ( "rx", "2.8" ), ( "ry", "6.5" ) ]
            , shape "path" [ ( "d", "M1.5 8h13" ) ]
            ]
        , langButton model PtBr "PT-BR" "português (Brasil)"
        , langButton model En "EN" "English"
        ]


linkedin : Locale -> Html msg
linkedin loc =
    Html.a
        [ cls "li"
        , attr "href" "https://www.linkedin.com/company/marola-dev/"
        , attr "target" "_blank"
        , attr "rel" "noopener"
        , attr "aria-label" (I18n.t loc "li.label" [])
        , attr "title" (I18n.t loc "li.label" [])
        ]
        [ svgIcon [ cls "li-mark", attr "viewBox" "0 0 24 24" ]
            [ shape "path" [ ( "d", "M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-4 0v7h-4v-7a6 6 0 0 1 6-6z" ) ]
            , shape "rect" [ ( "x", "2" ), ( "y", "9" ), ( "width", "4" ), ( "height", "12" ) ]
            , shape "circle" [ ( "cx", "4" ), ( "cy", "4" ), ( "r", "2" ) ]
            ]
        , Html.span [ cls "li-name" ] [ Html.text (I18n.t loc "li.name" []) ]
        ]


githubMark : String
githubMark =
    "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.06-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"


github : Locale -> Html msg
github loc =
    Html.a
        [ cls "gh"
        , attr "href" "https://github.com/marola-dev/marola"
        , attr "aria-label" (I18n.t loc "gh.label" [])
        , attr "title" (I18n.t loc "gh.title" [])
        ]
        [ svgIcon [ cls "gh-mark", attr "viewBox" "0 0 16 16" ]
            [ shape "path" [ ( "fill", "currentColor" ), ( "d", githubMark ) ] ]
        , Html.span [ cls "gh-name" ] [ Html.span [ cls "gh-owner" ] [ Html.text "marola-dev/" ], Html.text "marola" ]
        , Html.span [ cls "gh-star" ]
            [ svgIcon [ attr "viewBox" "0 0 16 16" ]
                [ shape "path" [ ( "d", "M8 1.6l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.4l-3.8 2 .7-4.3-3.1-3 4.3-.6z" ) ] ]
            , Html.span [] [ Html.text (I18n.t loc "gh.star" []) ]
            ]
        ]


view : Model -> Html Msg
view model =
    Html.nav
        [ cls "sitenav", attr "aria-label" (Words.t model "nav.label") ]
        [ link model "https://docs.marola.dev/" "nav.docs"
        , Html.span [ attr "aria-disabled" "true" ]
            [ Html.span [] [ Html.text (Words.t model "nav.alerts") ]
            , Html.text " "
            , Html.i [] [ Html.text (Words.t model "nav.soon") ]
            ]
        , link model "news.html" "nav.news"
        , link model "/studies" "nav.studies"
        , link model "about.html" "nav.about"
        , link model "contact.html" "nav.contact"
        , link model "https://github.com/marola-dev/marola-research/blob/main/README.md" "nav.research"
        , link model "https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf" "nav.contribute"
        , link model "members.html" "nav.members"
        , link model "support.html" "nav.donate"
        , languageToggle model
        , linkedin model.loc
        , github model.loc
        ]
