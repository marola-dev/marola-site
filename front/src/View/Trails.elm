module View.Trails exposing (card, panel, picked)

{-| The trails panel (routes grouped by bairro) and the card of a picked route.
-}

import Difficulty exposing (Difficulty(..))
import Fmt
import Href
import Html exposing (Html)
import Html.Keyed
import I18n
import Model exposing (Model, Panel(..), TrailsFile(..))
import Msg exposing (Msg(..))
import Trails exposing (Group, Route, Trails)
import Ui exposing (attr, cls, idAttr)
import Words


difficultyText : Model -> Route -> String
difficultyText model route =
    case route.difficulty of
        Hiking ->
            Words.t model "trails.hiking"

        MountainHiking ->
            Words.t model "trails.mountain_hiking"

        Unrated ->
            Words.t model "trails.unrated"

        Unknown raw ->
            raw


lengthText : Model -> Route -> String
lengthText model route =
    Fmt.value model.loc (Just route.lengthKm) " km" 1


difficultyBand : Route -> String
difficultyBand route =
    case route.difficulty of
        Hiking ->
            "c70"

        MountainHiking ->
            "c40"

        _ ->
            "cna"


routeItem : Model -> Int -> Route -> ( String, Html Msg )
routeItem model id route =
    ( String.fromInt id
    , Html.li []
        [ Html.button
            [ attr "type" "button"
            , attr "data-trail" (String.fromInt id)
            , cls "trail"
            , attr "aria-current"
                (if model.trailSelected == Just id then
                    "true"

                 else
                    "false"
                )
            , Ui.onClick (TrailChosen id True)
            ]
            [ Html.span [ cls ("score " ++ difficultyBand route) ] [ Html.text (difficultyText model route) ]
            , Html.text (route.name ++ " ")
            , Html.span [ cls "dist" ] [ Html.text (lengthText model route) ]
            ]
        ]
    )


{-| The groups with the position of their first route, which is its id on the map.
-}
numbered : List Group -> List ( Group, Int )
numbered groups =
    groups
        |> List.foldl (\group ( acc, first ) -> ( ( group, first ) :: acc, first + List.length group.routes )) ( [], 0 )
        |> Tuple.first
        |> List.reverse


groupView : Model -> ( Group, Int ) -> Html Msg
groupView model ( group, first ) =
    Html.section [ cls "trail-group" ]
        [ Html.h3 [] [ Html.text (Maybe.withDefault (Words.t model "trails.no_bairro") group.bairro) ]
        , Html.Keyed.node "ul" [] (List.indexedMap (\i route -> routeItem model (first + i) route) group.routes)
        ]


note : Trails -> List (Html Msg)
note found =
    case found.note of
        Just text ->
            [ Html.p [ cls "trail-note" ] [ Html.text text ] ]

        Nothing ->
            []


{-| The footer of the panel: the municipality, and where the lines come from.
-}
footer : Model -> Trails -> Html Msg
footer model found =
    let
        ibge =
            case found.ibgeMunicipality of
                Just code ->
                    [ Html.p [] [ Html.text (Words.ta model "trails.ibge" [ I18n.arg "code" code ]) ] ]

                Nothing ->
                    []

        licence =
            Maybe.map (\l -> ", " ++ l) found.licence |> Maybe.withDefault ""
    in
    Html.footer [ cls "trail-foot" ]
        (Html.p [] [ Html.text (Words.ta model "trails.source" [ I18n.arg "source" (found.source ++ licence) ]) ] :: ibge)


panelBody : Model -> List (Html Msg)
panelBody model =
    case ( model.trailsFile, Model.trails model ) of
        ( TrailsPending, _ ) ->
            [ Html.p [] [ Html.text (Words.t model "status.loading") ] ]

        ( _, Nothing ) ->
            [ Html.p [] [ Html.text (Words.t model "trails.empty") ] ]

        ( _, Just found ) ->
            if Trails.isEmpty found then
                -- An area with no routes says why, never an empty panel.
                (case found.note of
                    Just _ ->
                        note found

                    Nothing ->
                        [ Html.p [] [ Html.text (Words.t model "trails.empty") ] ]
                )
                    ++ [ footer model found ]

            else
                note found ++ List.map (groupView model) (numbered found.groups) ++ [ footer model found ]


panel : Model -> Html Msg
panel model =
    Html.aside
        ([ idAttr "trails-panel", cls "list trails", attr "aria-label" (Words.t model "flow.trails") ] ++ Ui.hidden (model.panel /= TrailList))
        (Html.h2 [] [ Html.text (Words.t model "flow.trails") ] :: panelBody model)


wayLink : Model -> Int -> List (Html Msg)
wayLink model id =
    case Href.safe (Trails.wayUrl id) of
        Just href ->
            [ Html.a [ attr "href" href, attr "target" "_blank", attr "rel" "noopener" ]
                [ Html.text (Words.ta model "trails.way" [ I18n.arg "id" (String.fromInt id) ]) ]
            ]

        Nothing ->
            []


row : Model -> String -> List (Html Msg) -> List (Html Msg)
row model k content =
    [ Html.dt [] [ Html.text (Words.t model k) ], Html.dd [] content ]


card : Model -> Route -> Html Msg
card model route =
    let
        surface =
            case route.surface of
                Just s ->
                    row model "trails.surface" [ Html.text s ]

                Nothing ->
                    []

        ways =
            case route.osmWays of
                [] ->
                    []

                ids ->
                    ids
                        |> List.indexedMap
                            (\i id ->
                                if i == 0 then
                                    wayLink model id

                                else
                                    Html.text " · " :: wayLink model id
                            )
                        |> List.concat
                        |> row model "trails.ways"
    in
    Html.section [ idAttr "card", cls "card trail-card", attr "aria-live" "polite" ]
        [ Html.button [ cls "close", attr "type" "button", attr "aria-label" (Words.t model "card.close"), Ui.onClick CardClosed ] [ Html.text "×" ]
        , Html.h2 [] [ Html.text route.name ]
        , Html.dl []
            (List.concat
                [ row model "trails.length" [ Html.text (lengthText model route) ]
                , row model "trails.difficulty" [ Html.text (difficultyText model route) ]
                , surface
                , ways
                ]
            )
        ]


{-| The route the card shows, if one is picked.
-}
picked : Model -> Maybe Route
picked model =
    case ( model.trailSelected, Model.trails model ) of
        ( Just id, Just found ) ->
            Trails.routeAt found id

        _ ->
            Nothing
