module View.List exposing (ranked, view)

import Band
import Beach exposing (Beach)
import Fmt
import Html exposing (Html)
import Html.Keyed
import Model exposing (Model, Panel(..))
import Msg exposing (Msg(..))
import Rank
import Ui exposing (attr, cls, idAttr)
import Water
import Words


{-| Each beach with its distance when the visitor shared a position.
-}
ranked : Model -> List ( Beach, Maybe Float )
ranked model =
    let
        beaches =
            Model.beaches model
    in
    case model.here of
        Just here ->
            Rank.byDistance beaches here |> List.map (\( b, km ) -> ( b, Just km ))

        Nothing ->
            Rank.byScore beaches model.selection |> List.map (\b -> ( b, Nothing ))


row : Model -> ( Beach, Maybe Float ) -> ( String, Html Msg )
row model ( beach, km ) =
    let
        shown =
            Beach.shown beach model.selection

        score =
            Maybe.map .score shown

        chip =
            Maybe.map String.fromInt score |> Maybe.withDefault "–"

        hour =
            Maybe.map .h shown |> Maybe.withDefault (Words.t model "list.dark")

        summary =
            Water.summaryText beach.water model.loc

        waterSpan =
            if beach.water.unfit then
                [ Html.text " ", Html.span [ cls "water unfit" ] [ Html.text summary ] ]

            else if not (List.isEmpty beach.water.points) then
                [ Html.text " ", Html.span [ cls "water" ] [ Html.text summary ] ]

            else
                []

        distance =
            case km of
                Just d ->
                    [ Html.text " ", Html.span [ cls "dist" ] [ Html.text (Fmt.num model.loc d 1 ++ " km") ] ]

                Nothing ->
                    []

        pick =
            BeachPicked beach.name True
    in
    ( beach.name
    , Html.li
        [ attr "data-name" beach.name, attr "tabindex" "0", attr "role" "button", Ui.onClick pick, Ui.onActivate pick ]
        ([ Html.span [ cls ("score " ++ Band.cssClass (Band.ofScore score beach.water.unfit)) ] [ Html.text chip ]
         , Html.text (beach.name ++ " ")
         , Html.span [ cls "dist" ] [ Html.text hour ]
         ]
            ++ distance
            ++ waterSpan
        )
    )


view : Model -> Html Msg
view model =
    Html.aside
        ([ idAttr "list", cls "list" ] ++ Ui.hidden (model.panel /= BeachList))
        [ Html.Keyed.node "ol" [] (List.map (row model) (ranked model)) ]
