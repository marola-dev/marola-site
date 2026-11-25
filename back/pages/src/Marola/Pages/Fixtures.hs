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

-- | A fixture beach: its name, coordinates and, when it has one, the IMA/SC sampling point the
-- offline preview shows. The point and verdict are real (the agency publishes both, and its
-- 17 Nov 2026 bulletin calls every point here PRÓPRIA); the enterococci count is absent because
-- that bulletin does not carry one.
data Place = Place Text Double Double (Maybe Sample)

data Sample = Sample
  { samplePoint :: Text,
    sampleLocation :: Text,
    sampleCondition :: Text,
    sampleEnterococci :: Maybe Int,
    sampleSummary :: Text,
    sampleUnfit :: Bool
  }

sample :: Text -> Text -> Maybe Sample
sample point location = Just (Sample point location "proper" Nothing ("1/1 PRÓPRIA (17 Nov)") False)

-- | Fixture beaches (not live data): the template board's beaches moved to real places in each
-- city, so the map centres on the city offline. Florianopolis keeps the template as it is. Point
-- coordinates move with their beach. The Complexo Lagunar entries are the IMA/SC lagoon and
-- lagoon-mouth points, so the water layer has real places to draw offline.
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
    )
  ]

boardFor :: A.Value -> Text -> A.Value
boardFor template area = case lookup area fixtureBeaches of
  Nothing -> template
  Just places -> overKey "beaches" (const (A.Array (V.fromList (zipWith build [0 ..] places)))) template
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
                "sampled_on" .= ("2026-11-17" :: Text),
                "enterococci_per_100ml" .= sampleEnterococci s,
                "rain" .= (Nothing :: Maybe Text)
              ]
          note =
            if sampleUnfit s
              then Just ("water unfit for bathing — IMA/SC 17 Nov 2026, " <> samplePoint s <> " (" <> sampleLocation s <> ")")
              else Nothing
       in set
            "water"
            ( A.object
                [ "summary" .= sampleSummary s,
                  "unfit" .= sampleUnfit s,
                  "note" .= note,
                  "source" .= ("IMA/SC" :: Text),
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
