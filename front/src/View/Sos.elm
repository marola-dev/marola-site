module View.Sos exposing (view)

import Html exposing (Html)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui exposing (attr, cls, idAttr)
import Words


numbers : List String
numbers =
    [ "193", "190", "192", "185", "199" ]


number : Model -> String -> Html Msg
number model n =
    Html.li []
        [ Html.a [ attr "href" ("tel:" ++ n) ]
            [ Html.b [] [ Html.text n ], Html.span [] [ Html.text (Words.t model ("sos." ++ n)) ] ]
        ]


onEscape : Html.Attribute Msg
onEscape =
    Ui.onKey
        (\key ->
            if key == "Escape" then
                Just SosClosed

            else
                Nothing
        )


view : Model -> List (Html Msg)
view model =
    [ Html.button
        [ idAttr "sos"
        , attr "type" "button"
        , cls "sos"
        , attr "aria-controls" "sos-panel"
        , Words.expanded model.sosOpen
        , Ui.onClick SosToggled
        ]
        [ Words.icon "phone", Html.span [] [ Html.text (Words.t model "sos.open") ] ]
    , Html.section
        ([ idAttr "sos-panel", cls "sos-panel", attr "aria-labelledby" "sos-title", onEscape ] ++ Ui.hidden (not model.sosOpen))
        [ Html.header []
            [ Html.h2 [ idAttr "sos-title" ] [ Html.text (Words.t model "sos.title") ]
            , Html.button
                [ idAttr "sos-close", attr "type" "button", attr "aria-label" (Words.t model "sos.close"), Ui.onClick SosClosed ]
                [ Html.text "×" ]
            ]
        , Html.p [] [ Html.text (Words.t model "sos.free") ]
        , Html.ul [] (List.map (number model) numbers)
        , Html.p [ cls "sos-note" ] [ Html.text (Words.t model "sos.mobile") ]
        ]
    ]
