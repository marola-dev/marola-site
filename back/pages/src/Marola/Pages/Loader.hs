-- | Reads the catalogs, the page Markdown, the news posts, the avatars and the areas from disk.
module Marola.Pages.Loader (readText, catalog, load) where

import Control.Monad (filterM, forM)
import Data.Aeson (FromJSON (..), withObject, (.:))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types qualified as Aeson
import Data.ByteString qualified as B
import Data.ByteString.Lazy qualified as BL
import Data.List (sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error qualified as TE
import Marola.Pages.I18n (Catalog)
import Marola.Pages.Language qualified as Language
import Marola.Pages.Site (Area (..), Env (..))
import Marola.Pages.Site qualified as Site
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (dropExtension, takeExtension, (</>))

-- | A file as text: UTF-8, a leading byte order mark dropped, a bad byte replaced rather than
-- fatal.
readText :: FilePath -> IO Text
readText p = do
  bytes <- B.readFile p
  let body = maybe bytes id (B.stripPrefix "\xEF\xBB\xBF" bytes)
  pure (TE.decodeUtf8With TE.lenientDecode body)

newtype AreaJson = AreaJson Area

-- lat and lon must be JSON numbers, as Decoders.number reads them; the pages do not use them.
instance FromJSON AreaJson where
  parseJSON = withObject "area" $ \o -> do
    i <- o .: "id"
    n <- o .: "name"
    _ <- (o .: "lat") >>= number
    _ <- (o .: "lon") >>= number
    pure (AreaJson (Area i n))
    where
      number :: Aeson.Value -> Aeson.Parser ()
      number (Aeson.Number _) = pure ()
      number _ = fail "Expecting a number"

-- | The file is @{"areas": [...]}@ on the site and a bare list in @site/areas.json@.
areasOf :: Aeson.Value -> Aeson.Parser [Area]
areasOf v = case v of
  Aeson.Array _ -> list v
  _ -> withObject "areas" (\o -> o .: "areas" >>= list) v
  where
    list x = map (\(AreaJson a) -> a) <$> parseJSON x

catalog :: FilePath -> IO (Either Text Catalog)
catalog dir = do
  parts <- forM Language.allLanguages $ \l -> do
    let name = T.unpack (Language.tag l) <> ".json"
    bytes <- BL.readFile (dir </> name)
    pure $ case Aeson.eitherDecode bytes :: Either String (Map Text Text) of
      Left e -> Left (T.pack name <> ": " <> T.pack e)
      Right m -> Right (l, m)
  pure (Map.fromList <$> sequence parts)

-- | @site@ is the @site/@ folder: @content/pages@ holds @<slug>.<tag>.md@ for every page and
-- language, @content/news@ the posts, @i18n@ the catalogs.
load :: FilePath -> Text -> IO (Either Text Env)
load site members = do
  let pages = site </> "content" </> "pages"
      news = site </> "content" </> "news"
      avatarsDir = site </> "static" </> "img" </> "members"
  files <- fmap catMaybes $
    forM [(s, l) | s <- Site.allSlugs, l <- Language.allLanguages] $ \(s, l) -> do
      let key = Site.contentKey s l
          p = pages </> T.unpack key <> ".md"
      exists <- doesFileExist p
      if exists then Just . (key,) <$> readText p else pure Nothing
  names <- sort . filter (\n -> takeExtension n == ".md") <$> listDirectory news
  postNames <- filterM (doesFileExist . (news </>)) (filter (/= "README.md") names)
  posts <- forM postNames $ \n -> (T.pack n,) <$> readText (news </> n)
  let index = news </> "README.md"
  hasIndex <- doesFileExist index
  indexText <- if hasIndex then readText index else pure ""
  areasBytes <- BL.readFile (site </> "areas.json")
  let areas = case Aeson.eitherDecode areasBytes >>= Aeson.parseEither areasOf of
        Left e -> Left ("areas.json: " <> T.pack e)
        Right as -> Right as
  hasAvatars <- doesDirectoryExist avatarsDir
  avatarFiles <- if hasAvatars then sort <$> listDirectory avatarsDir else pure []
  avatarPaths <- filterM (doesFileExist . (avatarsDir </>)) avatarFiles
  cat <- catalog (site </> "i18n")
  pure $ do
    c <- cat
    as <- areas
    Right
      Env
        { envCatalog = c,
          envContent = Map.fromList files,
          envNews = posts,
          envNewsIndex = indexText,
          envMembers = members,
          envAvatars = Map.fromList [(T.pack (dropExtension f), T.pack f) | f <- avatarPaths],
          envAreas = as
        }
