{-# LANGUAGE LambdaCase #-}

-- | The JSON files site_build.sh cannot make with shell alone: the page reads data/areas.json as
-- {"areas": [...]} while site/areas.json is a bare list, and with "boards" each area gets latest.json
-- plus the fixture board it names (offline preview).
module Marola.Pages.Fixtures (boardFor, main) where

import Data.Aeson ((.=))
import Data.Aeson qualified as A
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Vector qualified as V
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (takeDirectory, (</>))
import System.IO (hPutStrLn, stderr)

-- | A fixture beach: its name, coordinates and, when it has one, the agency sampling point the
-- offline preview shows. The points and verdicts are real: IMA/SC's bulletin of 17 Nov 2026 for
-- the Complexo Lagunar, IAT/PR's service of 9 Feb 2026 for the Litoral do Paraná. The enterococci
-- count is absent because neither bulletin carries one.
data Place = Place Text Double Double (Maybe Sample)

data Sample = Sample
  { samplePoint :: Text,
    sampleLocation :: Text,
    sampleCondition :: Text,
    sampleEnterococci :: Maybe Int,
    sampleSummary :: Text,
    sampleSource :: Text,
    sampleDay :: Text,
    sampleDayLabel :: Text,
    sampleUnfit :: Bool
  }

sample :: Text -> Text -> Maybe Sample
sample point location = Just (Sample point location "proper" Nothing "1/1 PRÓPRIA (17 Nov)" "IMA/SC" "2026-11-17" "17 Nov 2026" False)

sampleIat :: Text -> Text -> Bool -> Maybe Sample
sampleIat point location unfit =
  Just
    ( Sample
        point
        location
        (if unfit then "improper" else "proper")
        Nothing
        (if unfit then "0/1 IMPRÓPRIA (9 Feb)" else "1/1 PRÓPRIA (9 Feb)")
        "IAT/PR"
        "2026-02-09"
        "9 Feb 2026"
        unfit
    )

-- | Fixture beaches (not live data): the template board's beaches moved to real places in each
-- city, so the map centres on the city offline. Florianopolis keeps the template as it is. Point
-- coordinates move with their beach. The Complexo Lagunar entries are the IMA/SC lagoon and
-- lagoon-mouth points; the Litoral do Paraná ones are IAT/PR's coastal and river points, from the
-- Ilha do Mel to Guaratuba, so the water layer has real places to draw offline.
fixtureBeaches :: [(Text, [Place])]
fixtureBeaches =
  [ ("rio", [Place "Praia de Copacabana" (-22.9711) (-43.1822) Nothing, Place "Praia de Ipanema" (-22.9868) (-43.2058) Nothing]),
    ("salvador", [Place "Praia do Porto da Barra" (-13.0107) (-38.5326) Nothing, Place "Praia de Itapuã" (-12.9547) (-38.364) Nothing]),
    ( "complexo-lagunar",
      [ Place "Lagoa da Ferrugem" (-28.0812508) (-48.6320621) (sample "Ponto 04" "Lagoa da Ferrugem"),
        Place "Lagoa de Ibiraquera" (-28.1530163) (-48.6555733) (sample "Ponto 02" "Lagoa de Ibiraquera"),
        Place "Praia da Barra de Ibiraquera" (-28.1550308) (-48.6532467) (sample "Ponto 03" "Praia da Barra de Ibiraquera"),
        Place "Praia do Rosa" (-28.1353783) (-48.6429228) (sample "Ponto 01" "Praia do Rosa"),
        Place "Praia da Ribanceira" (-28.1908200) (-48.6626300) (sample "Ponto 04" "Praia da Ribanceira"),
        Place "Praia do Porto" (-28.2180632) (-48.6664049) (sample "Ponto 05" "Praia do Porto"),
        Place "Praia da Vila" (-28.2437216) (-48.6615419) (sample "Ponto 06" "Praia da Vila"),
        Place "Lagoa de Cabeçuda" (-28.4407007) (-48.8201088) (sample "Ponto 04" "Lagoa de Cabeçuda"),
        Place "Praia do Gi" (-28.4662117) (-48.7666425) (sample "Ponto 02" "Praia do Gi"),
        Place "Praia do Mar Grosso" (-28.4813661) (-48.7665704) (sample "Ponto 03" "Praia do Mar Grosso"),
        Place "Canal do Camacho" (-28.6093444) (-48.8608168) (sample "Ponto 03" "Canal do Camacho"),
        Place "Lagoa do Arroio Corrente" (-28.6920252) (-49.0185997) (sample "Ponto 02" "Lagoa do Arroio Corrente")
      ]
    ),
    ( "parana",
      [ Place "Praia do Farol" (-25.54039) (-48.30247) (sampleIat "IM01" "Farol (Praia do Farol)" False),
        Place "Praia Grande" (-25.54692) (-48.29421) (sampleIat "IM11" "Farol (Praia Grande)" False),
        Place "Encantadas" (-25.56418) (-48.31719) (sampleIat "IM10" "Encantadas (Baía)" False),
        Place "Pontal do Sul" (-25.57678) (-48.34889) (sampleIat "PS04" "Pontal do Sul" False),
        Place "Balneário Atami Sul" (-25.59934) (-48.38557) (sampleIat "AS01" "Balneário Atami Sul" False),
        Place "Praia de Leste" (-25.69929) (-48.46894) (sampleIat "LE03" "Praia de Leste" False),
        Place "Caiobá (Praia Mansa)" (-25.84786) (-48.54173) (sampleIat "CA10" "Caiobá (Praia Mansa)" False),
        Place "Matinhos Praia Central" (-25.81659) (-48.53177) (sampleIat "MS05" "Matinhos Praia Central" False),
        Place "Balneário Brejatuba" (-25.89981) (-48.56613) (sampleIat "GN5" "Balneário Brejatuba" True),
        Place "Barra do Saí" (-25.97484) (-48.59518) (sampleIat "GN1" "Barra do Saí" True),
        Place "Rio Nhundiaquara" (-25.47542) (-48.83303) (sampleIat "MR03" "Rio Nhundiaquara" True),
        Place "Ponta da Pita" (-25.45125) (-48.68476) (sampleIat "AT01" "Ponta da Pita" True)
      ]
    )
  ]

boardFor :: A.Value -> Text -> A.Value
boardFor template area = case lookup area fixtureBeaches of
  Nothing -> template
  Just places ->
    let boardSource = case [sampleSource s | Place _ _ _ (Just s) <- places] of
          source : _ -> source
          [] -> "IMA/SC"
     in overKey
          "sources"
          (overKey "water" (const (A.toJSON boardSource)))
          (overKey "beaches" (const (A.Array (V.fromList (zipWith build [0 ..] places)))) template)
  where
    templateBeaches = case template of
      A.Object o -> case KM.lookup "beaches" o of
        Just (A.Array xs) -> V.toList xs
        _ -> []
      _ -> []
    build :: Int -> Place -> A.Value
    build i (Place name lat lon found) =
      let base =
            case templateBeaches of
              [] -> A.Object KM.empty
              xs -> xs !! (i `mod` length xs)
          placed = set "lon" (A.toJSON lon) (set "lat" (A.toJSON lat) (set "name" (A.String name) base))
       in case found of
            Nothing -> movePoint name lat lon placed
            Just s -> setWater s lat lon placed
    movePoint name lat lon =
      overKey "water" (overKey "points" (overArray (const (set "lon" (A.toJSON lon) . set "lat" (A.toJSON lat) . set "location" (A.String name)))))
    setWater s lat lon beach =
      let point =
            A.object
              [ "point" .= samplePoint s,
                "location" .= sampleLocation s,
                "lat" .= lat,
                "lon" .= lon,
                "condition" .= sampleCondition s,
                "sampled_on" .= sampleDay s,
                "enterococci_per_100ml" .= sampleEnterococci s,
                "rain" .= (Nothing :: Maybe Text)
              ]
          note =
            if sampleUnfit s
              then Just ("water unfit for bathing — " <> sampleSource s <> " " <> sampleDayLabel s <> ", " <> samplePoint s <> " (" <> sampleLocation s <> ")")
              else Nothing
       in set
            "water"
            ( A.object
                [ "summary" .= sampleSummary s,
                  "unfit" .= sampleUnfit s,
                  "note" .= note,
                  "source" .= sampleSource s,
                  "points" .= [point]
                ]
            )
            beach

set :: Text -> A.Value -> A.Value -> A.Value
set k v = \case
  A.Object o -> A.Object (KM.insert (K.fromText k) v o)
  other -> other

overKey :: Text -> (A.Value -> A.Value) -> A.Value -> A.Value
overKey k f = \case
  A.Object o -> A.Object (maybe o (\v -> KM.insert (K.fromText k) (f v) o) (KM.lookup (K.fromText k) o))
  other -> other

overArray :: (Int -> A.Value -> A.Value) -> A.Value -> A.Value
overArray f = \case
  A.Array xs -> A.Array (V.imap f xs)
  other -> other

readJson :: FilePath -> IO A.Value
readJson p = either (\e -> fail (p <> ": " <> e)) pure =<< A.eitherDecodeFileStrict p

writeJson :: FilePath -> A.Value -> IO ()
writeJson p v = do
  createDirectoryIfMissing True (takeDirectory p)
  BL.writeFile p (A.encode v <> "\n")

main :: [String] -> IO ()
main = \case
  ["areas", dist] -> do
    areas <- readJson "site/areas.json"
    writeJson (dist </> "data" </> "areas.json") (A.object ["areas" .= areas])
  ["boards", dist] -> do
    areas <- readJson "site/areas.json"
    template <- readJson "site/fixtures/board.json"
    let day = case template of
          A.Object o | Just (A.String d) <- KM.lookup "day" o -> d
          _ -> ""
        file = day <> ".json"
        ids = case areas of
          A.Array xs -> [i | A.Object a <- V.toList xs, Just (A.String i) <- [KM.lookup "id" a]]
          _ -> []
    mapM_
      ( \area -> do
          let folder = dist </> "data" </> T.unpack area
          writeJson (folder </> "latest.json") (A.object ["days" .= [A.object ["day" .= day, "file" .= file]]])
          writeJson (folder </> T.unpack file) (boardFor template area)
      )
      ids
  _ -> do
    hPutStrLn stderr "usage: marola-pages fixtures <areas|boards> <dist-dir>"
    exitWith (ExitFailure 2)
