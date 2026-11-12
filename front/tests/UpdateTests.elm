module UpdateTests exposing (suite)

{-| The state machine against the fixture board and catalogs: what a visitor's action changes, and which effects it asks for.
-}

import Beach exposing (Selection(..))
import Effect exposing (Camera(..), Effect(..))
import Expect
import I18n
import Language
import Layer
import Model exposing (MapState(..), Panel(..), Status(..), TrailsFile(..))
import Msg exposing (FetchError(..), Fold(..), Loaded(..), Msg(..))
import Params
import Support exposing (areaNamed, browser, fixture, loaded, run, trailsSample)
import Test exposing (Test, describe, test)
import Update


page : String -> Model.Model
page search =
    Tuple.first (loaded search)


has : List Effect -> Effect -> Bool
has effects wanted =
    List.member wanted effects


syncs : List Effect -> List String
syncs =
    List.filterMap
        (\e ->
            case e of
                SyncMap text ->
                    Just text

                _ ->
                    Nothing
        )


isFit : Effect -> Bool
isFit e =
    case e of
        MoveCamera (Fit _ _ _ _ _ _ _) ->
            True

        _ ->
            False


isPan : Effect -> Bool
isPan e =
    case e of
        MoveCamera (Pan _ _) ->
            True

        _ ->
            False


withTrails : String -> Model.Model
withTrails search =
    Tuple.first (Update.update (TrailsFileLoaded "floripa" (Ok trailsSample)) (page search))


unchanged : Model.Model -> Msg -> Expect.Expectation
unchanged model msg =
    Update.update msg model |> Expect.equal ( model, [] )


all : List Expect.Expectation -> Expect.Expectation
all checks =
    Expect.all (List.map always checks) ()


suite : Test
suite =
    describe "update"
        [ test "init reads the links it understands" <|
            \_ ->
                let
                    ( model, effects ) =
                        Update.init (browser "?layer=water&beaches=0&lang=en&trails=0" [ "pt-BR" ])
                in
                all
                    [ Expect.equal model.layer Layer.Water
                    , Expect.equal model.showBeaches False
                    , Expect.equal model.showTrails False
                    , Expect.equal model.loc.language Language.En
                    , Expect.equal effects [ FetchCatalog Language.PtBr, FetchCatalog Language.En ]
                    ]
        , test "init ignores a layer whose button is off" <|
            \_ ->
                all
                    [ Expect.equal (Tuple.first (Update.init (browser "?layer=wind" []))).layer Layer.Off
                    , Expect.equal (Tuple.first (Update.init (browser "?layer=nonsense" []))).layer Layer.Off
                    ]
        , test "the page waits for both catalogs, then fetches the areas" <|
            \_ ->
                let
                    ( start, _ ) =
                        Update.init (browser "" [ "en-US" ])

                    ( one, first ) =
                        Update.update (CatalogLoaded Language.PtBr (Ok Support.emptyMessages)) start

                    ( both, second ) =
                        Update.update (CatalogLoaded Language.En (Ok Support.emptyMessages)) one
                in
                all
                    [ Expect.equal first []
                    , Expect.equal one.catalogsPending 1
                    , Expect.equal both.catalogsPending 0
                    , Expect.equal (has second FetchAreas) True
                    ]
        , test "a catalog that failed is said in the footer, and the page still goes on" <|
            \_ ->
                let
                    ( start, _ ) =
                        Update.init (browser "" [])

                    ( after, _ ) =
                        Update.update (CatalogLoaded Language.En (Err (HttpError 500))) start
                in
                all [ Expect.equal after.status (Failed "500 i18n/en.json" False), Expect.equal after.catalogsPending 1 ]
        , test "the area in the link wins over the first" <|
            \_ ->
                let
                    ( start, _ ) =
                        Update.init (browser "?area=rio" [])

                    ( model, effects ) =
                        Update.update (AreasLoaded (Ok [ areaNamed "floripa", areaNamed "rio" ])) start
                in
                all
                    [ Expect.equal model.area (Just (areaNamed "rio"))
                    , Expect.equal (has effects (FetchLatest "rio")) True
                    , Expect.equal (has effects (FetchTrails "rio")) True
                    , Expect.equal (has effects (InitMap -48.5 -27.6)) True
                    , Expect.equal model.map MapLoading
                    , Expect.equal (Params.get model.query "area") (Just "rio")
                    ]
        , test "no areas is a status, not a crash" <|
            \_ ->
                let
                    ( start, _ ) =
                        Update.init (browser "" [])
                in
                Expect.equal (Tuple.first (Update.update (AreasLoaded (Ok [])) start)).status NoAreas
        , test "the newest day loads unless the link names one" <|
            \_ ->
                let
                    days =
                        [ { date = "2026-09-06", file = "a.json" }, { date = "2026-09-07", file = "b.json" } ]

                    area =
                        AreasLoaded (Ok [ areaNamed "floripa" ])

                    effectsFor search =
                        Tuple.second (run (Tuple.first (Update.init (browser search []))) [ area, LatestLoaded "floripa" (Ok days) ])
                in
                all
                    [ Expect.equal (has (effectsFor "") (FetchBoard "floripa" "2026-09-07" "b.json")) True
                    , Expect.equal (has (effectsFor "?day=2026-09-06") (FetchBoard "floripa" "2026-09-06" "a.json")) True
                    ]
        , test "an answer for an area the visitor left is dropped" <|
            \_ ->
                unchanged (page "") (BoardLoaded "rio" fixture.day "x.json" (Ok (Read fixture)))
        , test "a board newer than the page is reported" <|
            \_ ->
                Expect.equal (Tuple.first (Update.update (BoardLoaded "floripa" fixture.day "x.json" (Ok (Newer 9))) (page ""))).status (TooNew 9)
        , test "a failed board says the status and the path" <|
            \_ ->
                Expect.equal (Tuple.first (Update.update (BoardLoaded "floripa" fixture.day "x.json" (Err (HttpError 404))) (page ""))).status (Failed "404 data/floripa/x.json" True)
        , test "a loaded board shows its beaches and fits the map once" <|
            \_ ->
                let
                    ( model, effects ) =
                        loaded ""

                    ( again, more ) =
                        Update.update (BoardLoaded "floripa" fixture.day "x.json" (Ok (Read fixture))) model
                in
                all
                    [ Expect.equal model.status Idle
                    , Expect.notEqual model.hours []
                    , Expect.equal model.fitted True
                    , Expect.equal (List.any isFit effects) True
                    , case syncs effects of
                        [ text ] ->
                            Expect.equal ( String.contains "Praia da Joaquina" text, String.contains "Praia Brava" text ) ( True, True )

                        other ->
                            Expect.fail ("expected one sync, got " ++ String.fromInt (List.length other))

                    -- The second board of the same area keeps the view the visitor has.
                    , Expect.equal (List.any isFit more) False
                    , Expect.equal again.fitted True
                    ]
        , test "a beach in the link opens its card" <|
            \_ ->
                all
                    [ Expect.equal (page "?beach=Praia%20Brava").selected (Just "Praia Brava")
                    , Expect.equal (page "?beach=Nowhere").selected Nothing
                    ]
        , test "picking and closing a beach keeps the link in step" <|
            \_ ->
                let
                    ( picked, effects ) =
                        Update.update (BeachPicked "Praia Brava" True) (page "")

                    ( closed, _ ) =
                        Update.update CardClosed picked
                in
                all
                    [ Expect.equal picked.selected (Just "Praia Brava")
                    , Expect.equal (has effects (ReplaceUrl "/" (Params.toString picked.query))) True
                    , Expect.equal (Params.get picked.query "beach") (Just "Praia Brava")
                    , Expect.equal (List.any isPan effects) True
                    , Expect.equal closed.selected Nothing
                    , Expect.equal (Params.get closed.query "beach") Nothing
                    ]
        , test "closing with nothing open changes nothing" <|
            \_ -> unchanged (page "") CardClosed
        , test "the slider moves between best hour and a clock hour" <|
            \_ ->
                let
                    model =
                        page ""

                    ( moved, _ ) =
                        Update.update (HourMoved 0) model
                in
                all
                    [ Expect.equal (Just moved.selection) (List.head model.hours |> Maybe.map At)
                    , Expect.equal (Tuple.first (Update.update (HourMoved -1) moved)).selection BestHour
                    , Expect.equal (Tuple.first (Update.update (HourMoved 999) moved)).selection BestHour
                    ]
        , test "a layer button that is off does nothing" <|
            \_ -> unchanged (page "") (LayerPressed Layer.Wind)
        , test "pressing the water layer twice turns it off" <|
            \_ ->
                let
                    ( on, _ ) =
                        Update.update (LayerPressed Layer.Water) (page "")
                in
                all
                    [ Expect.equal on.layer Layer.Water
                    , Expect.equal (Params.get on.query "layer") (Just "water")
                    , Expect.equal (Tuple.first (Update.update (LayerPressed Layer.Water) on)).layer Layer.Off
                    ]
        , test "the beach list and the trail panel never share the edge" <|
            \_ ->
                let
                    ( listOpen, _ ) =
                        Update.update ListToggled (page "")

                    ( trailsOpen, _ ) =
                        Update.update TrailPanelToggled listOpen
                in
                all
                    [ Expect.equal listOpen.panel BeachList
                    , Expect.equal trailsOpen.panel TrailList
                    , Expect.equal (Tuple.first (Update.update TrailPanelToggled trailsOpen)).panel Closed
                    ]
        , test "a style error before the map loads opens the list" <|
            \_ ->
                let
                    ( failed, _ ) =
                        Update.update (MapEvent "error" "style") (page "")
                in
                all [ Expect.equal failed.map (MapFailed "map.failed"), Expect.equal failed.panel BeachList ]
        , test "an error after the map is ready is ignored" <|
            \_ ->
                let
                    ( after, _ ) =
                        run (page "") [ MapEvent "ready" "", MapEvent "error" "tile" ]
                in
                all [ Expect.equal after.map MapReady, Expect.equal after.panel Closed ]
        , test "a click on a dot picks the beach without panning" <|
            \_ ->
                let
                    ( picked, effects ) =
                        Update.update (MapEvent "beach" "Praia Brava") (page "")
                in
                all [ Expect.equal picked.selected (Just "Praia Brava"), Expect.equal (List.any isPan effects) False ]
        , test "a click on the empty map closes the cards" <|
            \_ ->
                Expect.equal (Tuple.first (Update.update (MapEvent "click" "") (page "?beach=Praia%20Brava"))).selected Nothing
        , test "picking a language stores it and retitles the page" <|
            \_ ->
                let
                    ( after, effects ) =
                        Update.update (LanguagePicked Language.En) (page "")
                in
                all
                    [ Expect.equal after.loc.language Language.En
                    , Expect.equal (Params.get after.query "lang") (Just "en")
                    , Expect.equal (has effects (StoreLanguage Language.En)) True
                    , Expect.equal (has effects (SetDocument "en" "marola: sea conditions at every beach")) True
                    , Expect.notEqual (syncs effects) []
                    , Expect.equal
                        (List.any
                            (\e ->
                                case e of
                                    FetchBoard _ _ _ ->
                                        True

                                    _ ->
                                        False
                            )
                            effects
                        )
                        False
                    ]
        , test "the same language again changes nothing" <|
            \_ -> unchanged (page "") (LanguagePicked Language.PtBr)
        , test "a picked route closes the beach card" <|
            \_ ->
                let
                    ( picked, _ ) =
                        Update.update (TrailChosen 0 True) (withTrails "?beach=Praia%20Brava")
                in
                all
                    [ Expect.equal picked.trailSelected (Just 0)
                    , Expect.equal picked.selected Nothing
                    , Expect.equal (Params.get picked.query "beach") Nothing
                    ]
        , test "a route id that does not exist changes nothing" <|
            \_ -> unchanged (withTrails "") (TrailChosen 99999 True)
        , test "a missing trail file falls back to the board" <|
            \_ ->
                let
                    ( after, _ ) =
                        Update.update (TrailsFileLoaded "floripa" (Err NetworkError)) (page "")
                in
                all [ Expect.equal after.trailsFile TrailsMissing, Expect.notEqual (Model.trails after) Nothing ]
        , test "the location answer ranks by distance and opens the list" <|
            \_ ->
                let
                    here =
                        { lat = -27.6, lon = -48.5 }

                    ( after, _ ) =
                        Update.update (Located (Ok here)) (page "")
                in
                all
                    [ Expect.equal after.here (Just here)
                    , Expect.equal after.panel BeachList
                    , Expect.equal (Tuple.first (Update.update NearPressed after)).here Nothing
                    ]
        , test "a refused location is said in the page's language" <|
            \_ ->
                let
                    model =
                        page ""
                in
                Expect.equal (Tuple.second (Update.update (Located (Err "denied")) model)) [ Alert (I18n.t model.loc "near.denied" []) ]
        , test "the sound button flips the flag and a failure turns it off" <|
            \_ ->
                let
                    ( on, effects ) =
                        Update.update SoundPressed (page "")
                in
                all
                    [ Expect.equal on.soundOn True
                    , Expect.equal effects [ Sound True ]
                    , Expect.equal (Tuple.first (Update.update SoundFailed on)).soundOn False
                    ]
        , test "the SOS panel opens, and closing it gives the focus back" <|
            \_ ->
                let
                    ( on, _ ) =
                        Update.update SosToggled (page "")

                    ( off, effects ) =
                        Update.update SosClosed on
                in
                all
                    [ Expect.equal on.sosOpen True
                    , Expect.equal off.sosOpen False
                    , Expect.equal effects [ Focus "sos" ]
                    , unchanged off SosClosed
                    ]
        , test "the folds toggle on their own" <|
            \_ ->
                let
                    ( lore, _ ) =
                        Update.update (FoldToggled LoreFold) (page "")
                in
                all
                    [ Expect.equal ( lore.loreOpen, lore.blurbOpen ) ( True, False )
                    , Expect.equal (Tuple.first (Update.update (FoldToggled BlurbFold) lore)).blurbOpen True
                    ]
        , test "the beach and trail toggles write the link and redraw" <|
            \_ ->
                let
                    model =
                        page ""

                    ( off, effects ) =
                        Update.update BeachesToggled model
                in
                all
                    [ Expect.equal off.showBeaches False
                    , Expect.equal (Params.get off.query "beaches") (Just "0")
                    , Expect.notEqual (syncs effects) []
                    , Expect.equal (Params.get (Tuple.first (Update.update BeachesToggled off)).query "beaches") (Just "1")
                    , Expect.equal (Tuple.first (Update.update TrailsToggled model)).showTrails False
                    ]
        , test "picking an area starts afresh and fetches its data" <|
            \_ ->
                let
                    model =
                        page "?beach=Praia%20Brava"

                    ( after, effects ) =
                        Update.update (AreaPicked "rio") model

                    any pred =
                        List.any pred effects
                in
                all
                    [ Expect.equal after.area (Just (areaNamed "rio"))
                    , Expect.equal after.board Nothing
                    , Expect.equal after.selected Nothing
                    , Expect.equal (Params.get after.query "beach") Nothing
                    , Expect.equal (has effects (FetchLatest "rio")) True
                    , Expect.equal
                        (any
                            (\e ->
                                case e of
                                    InitMap _ _ ->
                                        True

                                    _ ->
                                        False
                            )
                        )
                        False
                    , Expect.equal
                        (any
                            (\e ->
                                case e of
                                    MoveCamera (Jump _ _ _) ->
                                        True

                                    _ ->
                                        False
                            )
                        )
                        True
                    , unchanged model (AreaPicked "nowhere")
                    ]
        ]
