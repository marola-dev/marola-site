module View.Bar exposing (hourIndex, hourLabel, tools)

import Area exposing (Area)
import Beach exposing (Selection(..))
import Board
import Config
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Html.Keyed
import I18n
import Json.Decode as D
import Json.Encode
import Model exposing (DayEntry, Model, Panel(..))
import Msg exposing (Msg(..))
import Ui exposing (attr, cls, idAttr)
import Words


{-| The iframe exists only while the player is open, so Spotify is not contacted before a click. Spotify's
compact embed carries its own link to the playlist, so the player is the iframe alone.
-}
player : Model -> Html Msg
player model =
    if model.playlistOpen then
        Html.section [ idAttr "player", cls "player", attr "aria-label" (Words.t model "player.label") ]
            [ Html.iframe
                [ attr "src" Config.playlistEmbed
                , attr "title" (Words.t model "player.label")
                , attr "allow" "autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture"
                , attr "loading" "lazy"
                ]
                []
            ]

    else
        Html.section ([ idAttr "player", cls "player" ] ++ Ui.hidden True) []


areaOption : Bool -> Area -> ( String, Html Msg )
areaOption selected a =
    ( a.id
    , Html.option
        [ attr "value" a.id, attr "title" a.name, attr "aria-label" a.name, Ui.flag "selected" selected ]
        [ Html.text (Config.areaCode a.id a.name) ]
    )


insta : Model -> Html Msg
insta model =
    let
        handle =
            model.area |> Maybe.andThen (\a -> Config.instagram a.id)

        city =
            Maybe.map .name model.area |> Maybe.withDefault ""
    in
    case handle of
        Nothing ->
            Html.a ([ idAttr "insta", cls "insta" ] ++ Ui.hidden True) []

        Just "" ->
            let
                soon =
                    Words.ta model "insta.soon" [ I18n.arg "city" city ]
            in
            Html.a
                [ idAttr "insta", cls "insta soon", attr "aria-disabled" "true", attr "aria-label" soon, attr "title" soon ]
                [ Words.icon "instagram", Html.span [] [ Html.text (Words.t model "nav.soon") ] ]

        Just name ->
            Html.a
                [ idAttr "insta"
                , cls "insta"
                , attr "href" ("https://www.instagram.com/" ++ name ++ "/")
                , attr "target" "_blank"
                , attr "rel" "noopener"
                , attr "aria-label" (Words.ta model "insta.label" [ I18n.arg "handle" ("@" ++ name) ])
                , attr "title" (Words.ta model "insta.title" [ I18n.arg "city" city ])
                ]
                [ Words.icon "instagram", Html.span [] [ Html.text ("@" ++ name) ] ]


monthDay : String -> String
monthDay date =
    if String.length date > 5 then
        String.dropLeft 5 date

    else
        ""


{-| A third day and later are named by their date alone, so the picker fits one row on a phone.
-}
dayLabel : Model -> Int -> DayEntry -> List (Html Msg)
dayLabel model index day =
    let
        date =
            Html.small [] [ Html.text (monthDay day.date) ]
    in
    case index of
        0 ->
            [ Html.text (Words.t model "day.today" ++ " "), date ]

        1 ->
            [ Html.text (Words.t model "day.tomorrow" ++ " "), date ]

        _ ->
            [ Html.text (monthDay day.date) ]


days : Model -> Html Msg
days model =
    Html.Keyed.node "div"
        [ idAttr "days", cls "segmented", attr "role" "group", attr "aria-label" (Words.t model "controls.day") ]
        (model.days
            |> List.indexedMap
                (\i day ->
                    ( day.date
                    , Html.button
                        ([ attr "type" "button", attr "data-day" day.date, Ui.onClick (DayPicked day.date) ]
                            ++ (if model.day == Just day.date then
                                    [ cls "on" ]

                                else
                                    []
                               )
                        )
                        (dayLabel model i day)
                    )
                )
        )


control : Model -> String -> String -> String -> String -> List (Html.Attribute Msg) -> Msg -> Html Msg
control model id iconName label title extra message =
    Html.button
        ([ idAttr id
         , attr "type" "button"
         , attr "title"
            (if title == "" then
                label

             else
                Words.t model title
            )
         , Ui.onClick message
         ]
            ++ extra
        )
        [ Words.icon iconName, Html.span [] [ Html.text label ] ]


{-| The slider's index: -1 is each beach at its own best hour.
-}
hourIndex : Model -> Int
hourIndex model =
    case model.selection of
        BestHour ->
            -1

        At h ->
            model.hours
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, x ) -> x == h)
                |> List.head
                |> Maybe.map Tuple.first
                |> Maybe.withDefault -1


hourLabel : Model -> String
hourLabel model =
    case ( model.selection, model.board ) of
        ( At h, Just b ) ->
            Words.ta model
                "hour.at"
                [ I18n.arg "h" h
                , I18n.arg "past"
                    (if Board.isPast b h then
                        "yes"

                     else
                        "no"
                    )
                ]

        _ ->
            Words.t model "hour.best"


chip : String -> List (Html Msg) -> Html Msg
chip band label =
    Html.span [] (Html.i [ cls band ] [] :: label)


legend : Model -> Html Msg
legend model =
    Html.span [ cls "legend", attr "aria-hidden" "true" ]
        [ Html.b [] [ Html.text (Words.t model "legend.score") ]
        , chip "c70" [ Html.text "≥70" ]
        , chip "c40" [ Html.text "40–69" ]
        , chip "c1" [ Html.text "1–39" ]
        , chip "c0" [ Html.span [] [ Html.text (Words.t model "legend.unfit") ] ]
        , chip "cna" [ Html.span [] [ Html.text (Words.t model "legend.no_data") ] ]
        , Html.span [ cls "wave-key" ] [ Html.span [] [ Html.text (Words.t model "legend.wave_key") ] ]
        ]


{-| A slider value that is not a number reads as the best hour.
-}
parseIndex : String -> Int
parseIndex value =
    String.toInt value |> Maybe.withDefault -1


hourbar : Model -> Html Msg
hourbar model =
    Html.div
        ([ idAttr "hourbar", cls "hourbar" ] ++ Ui.hidden (List.isEmpty model.hours))
        [ Html.label [ attr "for" "hour" ] [ Html.span [ idAttr "hour-label" ] [ Html.text (hourLabel model) ] ]

        -- The value is a property and comes after min and max: a range clamps to the bounds it has.
        , Html.input
            [ idAttr "hour"
            , attr "type" "range"
            , attr "min" "-1"
            , attr "max" (String.fromInt (List.length model.hours - 1))
            , attr "step" "1"
            , Html.Attributes.property "value" (Json.Encode.string (String.fromInt (hourIndex model)))
            , attr "aria-label" (Words.t model "hour.slider")
            , Html.Events.onInput (parseIndex >> HourMoved)
            ]
            []
        , legend model
        ]


{-| The tool row under the top bar: the controls, the hour slider with its legend, the tagline.
-}
tools : Model -> Html Msg
tools model =
    let
        picked =
            Maybe.map .id model.area |> Maybe.withDefault ""
    in
    Html.div [ cls "bar" ]
        [ Html.div [ cls "controls" ]
            [ Html.Keyed.node "select"
                [ idAttr "area"
                , attr "aria-label" (Words.t model "controls.area")
                , Html.Events.on "change" (D.map AreaPicked Html.Events.targetValue)
                ]
                (List.map (\a -> areaOption (a.id == picked) a) model.areas)
            , insta model
            , days model
            , control model "near" "locate" (Words.t model "controls.near") "controls.near_title" [ Words.pressed (model.here /= Nothing) ] NearPressed
            , control model "playlist" "music" (Words.t model "controls.playlist") "controls.playlist_title" [ Words.pressed model.playlistOpen, attr "aria-controls" "player" ] PlaylistPressed
            , control model
                "toggle-list"
                "list"
                (Words.t model "controls.list")
                ""
                [ attr "aria-controls" "list", Words.expanded (model.panel == BeachList) ]
                ListToggled
            ]
        , hourbar model
        , Html.p [ cls "tagline" ] [ Html.text (Words.t model "header.tagline") ]
        , player model
        ]
