module View.Footer exposing (statusLine, view)

{-| The footer: the status line, which reads as the board's provenance once a board is on show,
and the folds for the sea lore and for the privacy note.
-}

import Board exposing (Board)
import Config
import Href
import Html exposing (Html)
import I18n
import Lore exposing (Lore)
import Model exposing (Model, Status(..))
import Msg exposing (Fold(..), Msg(..))
import Ui exposing (attr, cls, idAttr)
import Words


yes : Bool -> String
yes on =
    if on then
        "yes"

    else
        "no"


source : String -> Html Msg
source name =
    let
        label =
            case Config.sourceLink name of
                Just href ->
                    Html.a [ attr "href" href, attr "target" "_blank", attr "rel" "noopener" ] [ Html.text name ]

                Nothing ->
                    Html.text name
    in
    Html.span [ cls "src" ] [ label ]


intersperse : a -> List a -> List a
intersperse sep items =
    case items of
        [] ->
            []

        first :: rest ->
            first :: List.concatMap (\item -> [ sep, item ]) rest


sources : Board -> List (Html Msg)
sources board =
    [ Just board.sources.beaches, Just board.sources.forecast, board.sources.water ]
        |> List.filterMap identity
        |> List.map source
        |> intersperse (Html.text " · ")


{-| The generation time as `YYYY-MM-DD HH:MM`.
-}
whenText : Board -> String
whenText board =
    String.replace "T" " " board.generatedAt |> String.left 16


provenance : Model -> Board -> List (Html Msg)
provenance model board =
    let
        area =
            Maybe.map .name model.area |> Maybe.withDefault board.area
    in
    Words.withSlot model
        "footer.generated"
        [ I18n.arg "when" (whenText board)
        , I18n.arg "area" area
        , I18n.arg "day" board.day
        , I18n.numberArg "n" (toFloat (List.length board.beaches))
        ]
        "sources"
        (sources board)


{-| What the status line says: a load in progress or failed, else the board.
-}
statusLine : Model -> List (Html Msg)
statusLine model =
    case model.status of
        Loading name ->
            [ Html.text (Words.ta model "status.loading_named" [ I18n.arg "name" name ]) ]

        Failed error missing ->
            [ Html.text (Words.ta model "fail.load" [ I18n.arg "error" error, I18n.arg "hint" (yes missing) ]) ]

        NoAreas ->
            [ Html.text (Words.t model "fail.no_areas") ]

        TooNew schema ->
            [ Html.text
                (Words.ta model
                    "fail.schema"
                    [ I18n.arg "got" (String.fromInt schema)
                    , I18n.arg "want" (List.map String.fromInt Board.schemas |> String.join ", ")
                    ]
                )
            ]

        Idle ->
            case model.board of
                Just board ->
                    provenance model board

                Nothing ->
                    [ Html.text (Words.t model "status.loading") ]


foldButton : String -> String -> Bool -> Msg -> Html Msg
foldButton id label open message =
    Html.button
        [ attr "type" "button"
        , cls "fold"
        , attr "data-fold" id
        , attr "aria-controls" ("footer-" ++ id)
        , Words.expanded open
        , Ui.onClick message
        ]
        [ Html.span [ cls "pm", attr "aria-hidden" "true" ] [], Html.text label ]


lorePanel : Model -> Lore -> Html Msg
lorePanel model found =
    let
        link =
            case Href.safe found.source of
                Just href ->
                    [ Html.text " "
                    , Html.a [ attr "href" href, attr "target" "_blank", attr "rel" "noopener" ]
                        [ Html.text ("[" ++ Words.t model "lore.source" ++ "]") ]
                    ]

                Nothing ->
                    []

        name =
            case found.kind of
                Lore.Creature ->
                    "fish"

                _ ->
                    "book"
    in
    Html.p
        ([ idAttr "footer-lore", cls "fold-panel lore" ] ++ Ui.hidden (not model.loreOpen))
        ([ Words.icon name, Html.text (" " ++ found.text) ] ++ link)


blurbPanel : Model -> Html Msg
blurbPanel model =
    Html.p
        ([ idAttr "footer-blurb", cls "fold-panel" ] ++ Ui.hidden (not model.blurbOpen))
        [ Html.text (Words.t model "footer.blurb" ++ " ")
        , Html.a [ attr "href" Config.repo, attr "target" "_blank", attr "rel" "noopener" ] [ Html.text (Words.t model "footer.github") ]
        , Html.text "."
        ]


view : Model -> Html Msg
view model =
    let
        lore =
            model.board |> Maybe.andThen .lore

        loreFold =
            case lore of
                Just found ->
                    [ foldButton "lore" (Words.t model (Lore.labelKey found.kind)) model.loreOpen (FoldToggled LoreFold) ]

                Nothing ->
                    []

        folds =
            loreFold
                ++ [ foldButton "blurb" (Words.t model "footer.about") model.blurbOpen (FoldToggled BlurbFold)

                   -- A placeholder for a feature not built yet: focusable and named, but it opens nothing.
                   , Html.button
                        [ attr "type" "button"
                        , cls "fold soon"
                        , attr "aria-disabled" "true"
                        , attr "aria-describedby" "footer-artists-soon"
                        , attr "title" (Words.t model "footer.artists_soon")
                        ]
                        [ Html.span [ cls "pm", attr "aria-hidden" "true" ] [], Html.text (Words.t model "footer.artists") ]
                   , Html.span [ idAttr "footer-artists-soon", cls "vh" ] [ Html.text (Words.t model "footer.artists_soon") ]
                   ]

        panels =
            (case lore of
                Just found ->
                    [ lorePanel model found ]

                Nothing ->
                    []
            )
                ++ [ blurbPanel model ]
    in
    Html.footer [ idAttr "footer", cls "footer" ]
        (Html.div [ cls "footbar" ]
            [ Html.p [ idAttr "status" ] (statusLine model)
            , Html.div [ cls "folds" ] folds
            ]
            :: panels
        )
