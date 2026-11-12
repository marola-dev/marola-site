module Support exposing (allClose, areaNamed, beachNamed, browser, catalog, check, close, emptyMessages, fixture, golden, goldenOne, langDecoder, loaded, locale, run, selection, trailsSample)

import Area exposing (Area)
import Beach exposing (Beach, Selection(..))
import Board exposing (Board)
import Dict exposing (Dict)
import Effect exposing (Effect)
import Expect exposing (Expectation)
import Fixtures
import I18n exposing (Catalog, Locale)
import Json.Decode as D exposing (Decoder)
import Language exposing (Language)
import Model exposing (Model)
import Msg exposing (Loaded(..), Msg(..))
import Params
import Trails exposing (Trails)
import Update exposing (Env)


decodeOrCrash : Decoder a -> String -> a
decodeOrCrash decoder text =
    case D.decodeString decoder text of
        Ok v ->
            v

        Err e ->
            Debug.todo ("bad fixture: " ++ D.errorToString e)


messages : String -> Dict String String
messages =
    decodeOrCrash I18n.messagesDecoder


emptyMessages : Dict String String
emptyMessages =
    Dict.empty


catalog : Catalog
catalog =
    Dict.fromList [ ( "pt-BR", messages Fixtures.catalogPtBr ), ( "en", messages Fixtures.catalogEn ) ]


locale : Language -> Locale
locale language =
    { catalog = catalog, language = language }


langDecoder : Decoder Language
langDecoder =
    D.string |> D.andThen (\tag -> Language.fromTag tag |> Maybe.map D.succeed |> Maybe.withDefault (D.fail tag))


golden : String -> Decoder a -> List a
golden section entry =
    decodeOrCrash (D.field section (D.list entry)) Fixtures.golden


goldenOne : String -> Decoder a -> a
goldenOne section decoder =
    decodeOrCrash (D.field section decoder) Fixtures.golden


variants : Dict String Beach
variants =
    decodeOrCrash (D.field "variants" (D.dict Beach.decoder)) Fixtures.golden


beachNamed : String -> Beach
beachNamed name =
    case Dict.get name variants of
        Just b ->
            b

        Nothing ->
            Debug.todo ("no golden beach " ++ name)


selection : Maybe String -> Selection
selection hour =
    case hour of
        Nothing ->
            BestHour

        Just h ->
            At h


{-| Relative tolerance, with the scale of the expected number held at 1 or more.
-}
close : Float -> Float -> Float -> Bool
close a b tolerance =
    abs (a - b) <= tolerance * max 1 (abs a)


allClose : List Float -> List Float -> Float -> Bool
allClose a b tolerance =
    List.length a == List.length b && List.all identity (List.map2 (\x y -> close x y tolerance) a b)


{-| Every case of a golden section, failing with the first few that differ.
-}
check : String -> Decoder a -> (a -> Maybe String) -> Expectation
check section entry test =
    let
        cases =
            golden section entry
    in
    case List.filterMap test cases of
        [] ->
            Expect.greaterThan 0 (List.length cases)

        failures ->
            Expect.fail (section ++ ": " ++ String.fromInt (List.length failures) ++ " of " ++ String.fromInt (List.length cases) ++ " differ:\n" ++ String.join "\n" (List.take 5 failures))


fixture : Board
fixture =
    decodeOrCrash Board.decoder Fixtures.board


browser : String -> List String -> Env
browser search languages =
    { path = "/", query = Params.parse search, languages = languages, storedLanguage = Nothing, reducedMotion = False }


areaNamed : String -> Area
areaNamed id =
    { id = id, name = "Area " ++ id, lat = -27.6, lon = -48.5 }


{-| Feeds each message to `Update.update`, keeping the effects of the last one.
-}
run : Model -> List Msg -> ( Model, List Effect )
run model msgs =
    List.foldl (\m ( state, _ ) -> Update.update m state) ( model, [] ) msgs


{-| A page that has loaded its catalogs, an area, a day and the fixture board.
-}
loaded : String -> ( Model, List Effect )
loaded search =
    let
        ( start, _ ) =
            Update.init (browser search [ "pt-BR" ])

        b =
            fixture
    in
    run start
        [ CatalogLoaded Language.PtBr (Ok (messages Fixtures.catalogPtBr))
        , CatalogLoaded Language.En (Ok (messages Fixtures.catalogEn))
        , AreasLoaded (Ok [ areaNamed "floripa", areaNamed "rio" ])
        , LatestLoaded "floripa" (Ok [ { date = b.day, file = b.day ++ ".json" } ])
        , BoardLoaded "floripa" b.day (b.day ++ ".json") (Ok (Read b))
        ]


{-| A trails file of two bairros and three routes, the second with no drawable line.
-}
trailsSample : Trails
trailsSample =
    decodeOrCrash Trails.decoder """
{"schema":1,"area":"floripa","ibge_municipality":"4205407","source":"OpenStreetMap contributors","licence":"ODbL-1.0",
 "osm_base":"2026-09-01T00:00:00Z","bairros":[
  {"bairro":"Lagoa","trails":[
    {"name":"Trilha A","length_km":1.5,"difficulty":"hiking","surface":"dirt","osm_ways":[1,2],"lines":[[[-27.6,-48.45],[-27.61,-48.46]]]},
    {"name":"Trilha B","length_km":0.4,"difficulty":null,"surface":null,"osm_ways":[3],"lines":[[[-27.6,-48.45]]]}]},
  {"bairro":"Campeche","trails":[
    {"name":"Trilha C","length_km":3,"difficulty":"mountain_hiking","surface":null,"osm_ways":[4],"lines":[[[-27.7,-48.5],[-27.71,-48.51],[-27.72,-48.52]]]}]}]}
"""
