module View.Card exposing (fixed4, view)

{-| The card of the picked beach. Touch has no hover, so it opens with the tooltip's aspect row
(MIP-0009 section 3).
-}

import Aspects
import AspectsView
import Band
import Beach exposing (Beach, Tide)
import Board
import Fmt
import Hour exposing (Shown)
import Html exposing (Html)
import I18n
import Level
import Model exposing (Model)
import Msg exposing (Msg(..))
import Notes
import Tree
import Ui exposing (attr, cls, idAttr)
import Water exposing (Condition(..), WaterPoint)
import Words


yes : Bool -> String
yes on =
    if on then
        "yes"

    else
        "no"


{-| Coordinates keep the dot in every language: a decimal comma would collide with the separator.
Half away from zero on the magnitude; the sign comes back after.
-}
fixed4 : Float -> String
fixed4 n =
    let
        scaled =
            floor (abs n * 10000 + 0.5)

        sign =
            if n < 0 && scaled /= 0 then
                "-"

            else
                ""
    in
    sign ++ String.fromInt (scaled // 10000) ++ "." ++ String.padLeft 4 '0' (String.fromInt (modBy 10000 scaled))


{-| A float as a URL carries it: always with a point.
-}
plain : Float -> String
plain n =
    let
        s =
            String.fromFloat n
    in
    if String.contains "." s || String.contains "e" s || String.contains "E" s then
        s

    else
        s ++ ".0"


headline : Model -> Beach -> Maybe Shown -> Html Msg
headline model b shown =
    case shown of
        Nothing ->
            Html.p [ cls "headline past" ] [ Html.text (Words.t model "tip.dark") ]

        Just s ->
            let
                past =
                    Maybe.map (\board -> Board.isPast board s.h) model.board |> Maybe.withDefault False

                at =
                    Html.b [] [ Html.text s.h ]

                words =
                    if s.best then
                        Words.withSlot model "card.best_at" [] "h" [ at ]

                    else
                        Words.withSlot model "card.at_best" [ I18n.arg "best" b.best.hour, I18n.arg "score" (String.fromInt b.best.score) ] "h" [ at ]

                pastTag =
                    if past then
                        [ Html.text " ", Html.span [ cls "past" ] [ Html.text (Words.t model "card.past") ] ]

                    else
                        []
            in
            Html.p [ cls "headline" ]
                ([ Html.span [ cls ("score " ++ Band.cssClass (Band.ofScore (Just s.score) b.water.unfit)) ] [ Html.text (String.fromInt s.score ++ "/100") ]
                 , Html.text " "
                 ]
                    ++ words
                    ++ pastTag
                )


why : Model -> Maybe Shown -> Html Msg
why model shown =
    case Maybe.map (\s -> Notes.ofShown s model.loc) shown of
        Just ((_ :: _) as lines) ->
            Html.ul [] (List.map (\n -> Html.li [] [ Html.text n ]) lines)

        _ ->
            Html.text (Words.t model "card.good")


conditionClass : Condition -> String
conditionClass condition =
    case condition of
        Improper ->
            "water improper"

        Proper ->
            "water proper"

        _ ->
            "water"


pointItem : Model -> WaterPoint -> Html Msg
pointItem model p =
    let
        count =
            case p.enterococciPer100ml of
                Just n ->
                    [ Html.text (", " ++ Words.ta model "card.enterococci" [ I18n.arg "n" (String.fromInt n) ]) ]

                Nothing ->
                    []
    in
    Html.li []
        ([ Html.span [ cls (conditionClass p.condition) ] [ Html.text (p.point ++ " (" ++ p.location ++ "): " ++ Water.conditionLabel p.condition model.loc) ]
         , Html.text (", " ++ p.sampledOn)
         ]
            ++ count
        )


waterCell : Model -> Beach -> List (Html Msg)
waterCell model b =
    let
        points =
            case b.water.points of
                [] ->
                    []

                found ->
                    [ Html.ul [] (List.map (pointItem model) found) ]

        source =
            case b.water.source of
                Just s ->
                    [ Html.small [] (Words.withSlot model "card.source" [] "source" [ Html.span [ cls "src" ] [ Html.text s ] ]) ]

                Nothing ->
                    []
    in
    [ Html.span
        [ cls
            (if b.water.unfit then
                "unfit"

             else
                "water"
            )
        ]
        [ Html.text (Water.summaryText b.water model.loc) ]
    ]
        ++ points
        ++ source


tideText : Model -> Tide -> String
tideText model tide =
    Words.ta model
        (if tide.high then
            "tide.high"

         else
            "tide.low"
        )
        [ I18n.arg "time" tide.time, I18n.arg "m" (Fmt.signed model.loc tide.m 1) ]


tidesCell : Model -> Beach -> List (Html Msg)
tidesCell model b =
    case b.tides of
        [] ->
            [ Html.text (Words.t model "tide.none") ]

        tides ->
            [ Html.text ((List.map (tideText model) tides |> String.join ", ") ++ " ")
            , Html.small [] [ Html.text (Words.t model "tide.hourly") ]
            ]


seaText : Model -> Beach -> String
seaText model b =
    let
        sea =
            b.sea

        loc =
            model.loc

        extra value key unit =
            case value of
                Just _ ->
                    [ Words.ta model key [ I18n.arg "v" (Fmt.value loc value unit 1) ] ]

                Nothing ->
                    []
    in
    [ [ Fmt.value loc sea.tempC "°C" 1, Fmt.waves loc sea.waveM sea.periodS ]
    , extra sea.swellM "card.swell" " m"
    , extra sea.currentKmh "card.current" " km/h"
    ]
        |> List.concat
        |> String.join ", "


airText : Model -> Beach -> String
airText model b =
    let
        sea =
            b.sea

        loc =
            model.loc
    in
    [ [ Fmt.value loc sea.airTempC "°C" 0
      , Words.ta model "cell.wind" [ I18n.arg "v" (Fmt.value loc sea.windKmh " km/h" 0) ]
      ]
    , case sea.uv of
        Just _ ->
            [ Words.ta model "card.uv" [ I18n.arg "v" (Fmt.value loc sea.uv "" 0) ] ]

        Nothing ->
            []
    , case sea.rainPct of
        Just pct ->
            [ Words.ta model "card.rain" [ I18n.arg "pct" (Fmt.num loc pct 0) ] ]

        Nothing ->
            []
    ]
        |> List.concat
        |> String.join ", "


whalesText : Model -> Beach -> String
whalesText model b =
    Words.ta model
        "card.whales_now"
        [ I18n.arg "level" (I18n.word model.loc "lvl." (Level.toString b.whales.now))
        , I18n.arg "best" (yes (b.whales.peak /= Nothing))
        , I18n.arg "peak" (Maybe.withDefault "" b.whales.peak)
        , I18n.arg "season" (yes b.whales.season)
        ]


whereCell : Beach -> Html Msg
whereCell b =
    let
        lat =
            plain b.lat

        lon =
            plain b.lon
    in
    Html.a
        [ attr "href" ("https://www.openstreetmap.org/?mlat=" ++ lat ++ "&mlon=" ++ lon ++ "#map=15/" ++ lat ++ "/" ++ lon)
        , attr "target" "_blank"
        , attr "rel" "noopener"
        ]
        [ Html.text (fixed4 b.lat ++ ", " ++ fixed4 b.lon) ]


row : Model -> String -> List (Html Msg) -> List (Html Msg)
row model key content =
    [ Html.dt [] [ Html.text (Words.t model key) ], Html.dd [] content ]


metric : Model -> String -> List (Html Msg) -> String -> String -> Html Msg
metric model key lead number unit =
    Html.div [ cls "metric" ]
        [ Html.b [] (lead ++ [ Html.text number, Html.small [] [ Html.text unit ] ])
        , Html.span [] [ Html.text (Words.t model key) ]
        ]


{-| The hour on show at a glance: the score and three readings of that hour, each a numeral over
its label. A beach dark at that hour shows dashes.
-}
metrics : Model -> Beach -> Maybe Shown -> Html Msg
metrics model b shown =
    let
        entry =
            Beach.hourEntry b shown

        score =
            Maybe.map .score shown

        reading pick digits =
            entry |> Maybe.andThen pick |> Maybe.map (\v -> Fmt.num model.loc v digits) |> Maybe.withDefault "–"

        dot =
            Html.i [ cls (Band.cssClass (Band.ofScore score b.water.unfit)) ] []
    in
    Html.div [ cls "metrics" ]
        [ metric model "metric.score" [ dot ] (Maybe.map String.fromInt score |> Maybe.withDefault "–") "/100"
        , metric model "metric.wind" [] (reading .windKmh 0) "km/h"
        , metric model "metric.waves" [] (reading .waveM 1) "m"
        , metric model "metric.water" [] (reading .seaTempC 1) "°C"
        ]


body : Model -> Beach -> Html Msg
body model b =
    let
        shown =
            Beach.shown b model.selection

        tip =
            Aspects.ofBeach b shown model.loc
    in
    Html.section [ idAttr "card", cls "card", attr "aria-live" "polite" ]
        [ Html.button [ cls "close", attr "type" "button", attr "aria-label" (Words.t model "card.close"), Ui.onClick CardClosed ] [ Html.text "×" ]
        , Html.h2 [] [ Html.text b.name ]
        , headline model b shown
        , metrics model b shown
        , Html.div [ cls "aspects" ] (List.map Tree.toHtml (AspectsView.children tip))
        , Html.dl []
            (List.concat
                [ row model "card.why" [ why model shown ]
                , row model "card.water" (waterCell model b)
                , row model "card.sea" [ Html.text (seaText model b ++ " "), Html.small [] [ Html.text (Words.ta model "card.at" [ I18n.arg "h" b.best.hour ]) ] ]
                , row model "card.tide" (tidesCell model b)
                , row model "card.air" [ Html.text (airText model b) ]
                , row model "card.jellyfish" [ Html.text (I18n.word model.loc "lvl." (Level.toString b.jellyfish)) ]
                , row model "card.whales" [ Html.text (whalesText model b) ]
                , row model "card.where" [ whereCell b ]
                ]
            )
        ]


view : Model -> Html Msg
view model =
    let
        picked =
            case ( model.selected, model.board ) of
                ( Just name, Just board ) ->
                    List.filter (\b -> b.name == name) board.beaches |> List.head

                _ ->
                    Nothing
    in
    case picked of
        Just b ->
            body model b

        Nothing ->
            Html.section ([ idAttr "card", cls "card" ] ++ Ui.hidden True) []
