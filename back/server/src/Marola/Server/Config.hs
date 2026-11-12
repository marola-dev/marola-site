-- | Where the server listens and what it reads and writes. The variable names are
-- docs/5-hosting.md's, which the nix-os module sets.
module Marola.Server.Config (Config (..), fromEnv, fromProcessEnv) where

import Data.Char (isSpace)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import System.Directory (makeAbsolute)
import System.Environment (lookupEnv)
import System.FilePath (normalise)
import Text.Read (readMaybe)

data Config = Config
  { port :: Int,
    -- | The built page (@dist@, scripts/site_build.sh): served at @/@.
    static :: FilePath,
    -- | The board data folder: @/data/<x>@ is looked up here first, then under 'static'.
    dataDir :: FilePath,
    db :: FilePath,
    -- | The PDFs, as @<sha256>.pdf@. Outside 'static', never served as a file tree.
    studies :: FilePath,
    studiesQuota :: Int64,
    -- | The folder of the base map's PMTiles file: @/tiles/<name>.pmtiles@ is looked up here first,
    -- then under 'static'. Host data, like 'dataDir': never part of the build.
    tiles :: FilePath,
    -- | @MAROLA_DEV=1@: cookies without @Secure@ and the @__Host-@ prefix, and the GitHub URLs may be
    -- overridden. For the smoke script on plain HTTP and a fake GitHub; never set in production.
    dev :: Bool,
    githubClientId :: Maybe Text,
    -- | The file that holds the OAuth client secret. The secret itself is never in the environment.
    githubSecretFile :: Maybe FilePath,
    githubBase :: Text,
    githubApiBase :: Text
  }
  deriving (Show)

-- | Reads the MAROLA_* variables through @get@, so a test passes a map and not the process environment.
fromEnv :: (String -> Maybe String) -> IO (Either String Config)
fromEnv get = do
  let nonEmpty n = case get n of
        Just v | not (all isSpace v) -> Just v
        _ -> Nothing
      absolute p = normalise <$> makeAbsolute p
      pathOf n fallback = absolute (maybe fallback id (nonEmpty n))
      dev = get "MAROLA_DEV" == Just "1"
      -- A URL override only counts in dev mode: in production the OAuth code and secret go to github.com.
      url n fallback = if dev then maybe fallback T.pack (nonEmpty n) else fallback
      port = case get "MAROLA_PORT" of
        Nothing -> Right 8080
        Just s -> case readMaybe s :: Maybe Int of
          Just p | p >= 1 && p <= 65535 && all (`elem` ("0123456789+" :: String)) s -> Right p
          _ -> Left ("MAROLA_PORT is not a port number: " <> s)
      quota = case get "MAROLA_STUDIES_QUOTA" of
        Nothing -> Right (2 * 1024 * 1024 * 1024)
        Just s -> case readMaybe s :: Maybe Int64 of
          Just n | n >= 1 -> Right n
          _ -> Left ("MAROLA_STUDIES_QUOTA is not a number of bytes: " <> s)
  case (,) <$> port <*> quota of
    Left e -> pure (Left e)
    Right (p, q) -> do
      st <- pathOf "MAROLA_STATIC" "dist"
      da <- pathOf "MAROLA_DATA" "data"
      d <- pathOf "MAROLA_DB" "data/marola.db"
      su <- pathOf "MAROLA_STUDIES" "data/studies"
      ti <- pathOf "MAROLA_TILES" "data/tiles"
      secret <- traverse absolute (nonEmpty "MAROLA_GITHUB_CLIENT_SECRET_FILE")
      pure . Right $
        Config
          { port = p,
            static = st,
            dataDir = da,
            db = d,
            studies = su,
            studiesQuota = q,
            tiles = ti,
            dev = dev,
            githubClientId = T.pack <$> nonEmpty "MAROLA_GITHUB_CLIENT_ID",
            githubSecretFile = secret,
            githubBase = url "MAROLA_GITHUB_BASE" "https://github.com",
            githubApiBase = url "MAROLA_GITHUB_API_BASE" "https://api.github.com"
          }

fromProcessEnv :: IO (Either String Config)
fromProcessEnv = do
  let names =
        [ "MAROLA_PORT",
          "MAROLA_STUDIES_QUOTA",
          "MAROLA_STATIC",
          "MAROLA_DATA",
          "MAROLA_DB",
          "MAROLA_STUDIES",
          "MAROLA_TILES",
          "MAROLA_DEV",
          "MAROLA_GITHUB_CLIENT_ID",
          "MAROLA_GITHUB_CLIENT_SECRET_FILE",
          "MAROLA_GITHUB_BASE",
          "MAROLA_GITHUB_API_BASE"
        ]
  values <- mapM (\n -> (n,) <$> lookupEnv n) names
  fromEnv (\n -> maybe Nothing id (lookup n values))
