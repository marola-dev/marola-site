module View.Watermark exposing (view)

{-| The map's watermark, bottom left: piabrota's eye and "leave no trace", one colour, faint. Plain
text and marola's own mark only: Leave No Trace's partner logo waits on the partnership's terms
(marola-dev/marola-site#96).
-}

import Html exposing (Html)
import Model exposing (Model)
import Msg exposing (Msg)
import Svg
import Ui exposing (attr, cls, idAttr)
import Words


{-| `View.Nav.eye` as one even-odd path in `currentColor`: the tile, the eye's white cut out, the
iris filled, the pupil cut out.
-}
eye : Html msg
eye =
    Svg.svg [ attr "viewBox" "0 0 100 100", attr "aria-hidden" "true", attr "focusable" "false" ]
        [ Svg.node "path"
            [ attr "fill" "currentColor"
            , attr "fill-rule" "evenodd"
            , attr "d"
                ("M22 0H78A22 22 0 0 1 100 22V78A22 22 0 0 1 78 100H22A22 22 0 0 1 0 78V22A22 22 0 0 1 22 0Z"
                    ++ "M12 50Q50 18 88 50Q50 82 12 50Z"
                    ++ "M36 50A14 14 0 1 0 64 50A14 14 0 1 0 36 50Z"
                    ++ "M44 50A6 6 0 1 0 56 50A6 6 0 1 0 44 50Z"
                )
            ]
            []
        ]


view : Model -> Html Msg
view model =
    Html.p [ idAttr "watermark", cls "watermark" ]
        [ eye, Html.span [] [ Html.text (Words.t model "map.lnt") ] ]
