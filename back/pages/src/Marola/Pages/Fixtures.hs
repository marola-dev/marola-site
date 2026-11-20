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

-- | Fixture beaches (not live data): the template board's two beaches moved to real places in each
-- city, so the map centres on the city offline. Florianopolis keeps the template as it is. Point
-- coordinates move with their beach.
fixtureBeaches :: [(Text, [(Text, Double, Double)])]
fixtureBeaches =
  [ ("rio", [("Praia de Copacabana", -22.9711, -43.1822), ("Praia de Ipanema", -22.9868, -43.2058)]),
    ("salvador", [("Praia do Porto da Barra", -13.0107, -38.5326), ("Praia de Itapuã", -12.9547, -38.364)])
  ]

boardFor :: A.Value -> Text -> A.Value
boardFor template area = case lookup area fixtureBeaches of
  Nothing -> template
  Just places -> overKey "beaches" (overArray (\i b -> maybe b (move b) (lookupAt i places))) template
  where
    lookupAt i xs = case drop i xs of
      (x : _) -> Just x
      [] -> Nothing
    move beach (name, lat, lon) =
      let placed = set "lon" (A.toJSON lon) (set "lat" (A.toJSON lat) (set "name" (A.String name) beach))
          point = set "lon" (A.toJSON lon) . set "lat" (A.toJSON lat) . set "location" (A.String name)
       in overKey "water" (overKey "points" (overArray (const point))) placed

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
