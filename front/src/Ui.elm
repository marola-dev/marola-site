module Ui exposing (attr, cls, flag, hidden, idAttr, onActivate, onClick, onKey)

{-| Attributes as the F# page set them: `setAttribute` for every name, so the DOM reads the same
and `style.css` keeps working; events through Elm, never an `on...` attribute, which the CSP
blocks.
-}

import Html exposing (Attribute)
import Html.Attributes
import Html.Events
import Json.Decode as D
import Json.Encode as E


attr : String -> String -> Attribute msg
attr =
    Html.Attributes.attribute


cls : String -> Attribute msg
cls =
    attr "class"


idAttr : String -> Attribute msg
idAttr =
    attr "id"


{-| A boolean property: `disabled`, `selected`.
-}
flag : String -> Bool -> Attribute msg
flag name on =
    Html.Attributes.property name (E.bool on)


{-| The `hidden` attribute when `on`, else nothing.
-}
hidden : Bool -> List (Attribute msg)
hidden on =
    if on then
        [ attr "hidden" "" ]

    else
        []


onClick : msg -> Attribute msg
onClick =
    Html.Events.onClick


{-| A key that dispatches also loses its default: Space on a focused control would scroll.
-}
onKey : (String -> Maybe msg) -> Attribute msg
onKey pick =
    Html.Events.preventDefaultOn "keydown"
        (D.field "key" D.string
            |> D.andThen
                (\key ->
                    case pick key of
                        Just msg ->
                            D.succeed ( msg, True )

                        Nothing ->
                            D.fail "not handled"
                )
        )


{-| Enter or Space on a focused element does what a click does.
-}
onActivate : msg -> Attribute msg
onActivate msg =
    onKey
        (\key ->
            if key == "Enter" || key == " " then
                Just msg

            else
                Nothing
        )
