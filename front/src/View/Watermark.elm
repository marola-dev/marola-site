module View.Watermark exposing (view)

{-| The map's watermark, bottom left: Leave No Trace's Proud Partner logo, the PNG Leave No Trace
supplies, unchanged (`vendor/lnt/`, marola is a partner: the umbrella's PARTNERS.en.md), and
piabrota's eye in one colour beside it. The logo is the `.lnt` span's CSS background, like `.logo`:
the page holds no `<img>` (`scripts/front_check.js` asserts it).
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
        [ Html.span [ cls "lnt", attr "role" "img", attr "aria-label" (Words.t model "map.lnt") ] []
        , eye
        ]
