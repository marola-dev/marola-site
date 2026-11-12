module Words exposing (expanded, icon, pressed, t, ta, withSlot)

{-| Words for the view: a catalog message, plain or with a piece of markup in the middle. The
markup is never part of a message: the piece is a node put where a marker stood, so a message
cannot inject any. A missing key renders the key.
-}

import Html exposing (Attribute, Html)
import Html.Attributes exposing (attribute)
import I18n
import Icons
import Icu
import Model exposing (Model)
import Tree


t : Model -> String -> String
t model key =
    I18n.t model.loc key []


ta : Model -> String -> List ( String, Icu.Arg ) -> String
ta model key args =
    I18n.t model.loc key args


{-| A private-use character no catalog message contains.
-}
marker : String
marker =
    "\u{E000}"


{-| The message with `slot` where the argument `name` is. A message that does not use the argument
(a branch of a `select`) comes back as text alone.
-}
withSlot : Model -> String -> List ( String, Icu.Arg ) -> String -> List (Html msg) -> List (Html msg)
withSlot model key args name slot =
    I18n.t model.loc key (I18n.arg name marker :: args)
        |> String.split marker
        |> List.indexedMap
            (\i part ->
                if i == 0 then
                    [ Html.text part ]

                else
                    slot ++ [ Html.text part ]
            )
        |> List.concat


pressed : Bool -> Attribute msg
pressed on =
    attribute "aria-pressed"
        (if on then
            "true"

         else
            "false"
        )


expanded : Bool -> Attribute msg
expanded on =
    attribute "aria-expanded"
        (if on then
            "true"

         else
            "false"
        )


icon : String -> Html msg
icon name =
    Tree.toHtml (Icons.icon name)
