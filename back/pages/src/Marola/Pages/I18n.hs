-- | The message catalog and @t@.
module Marola.Pages.I18n (Catalog, Locale (..), lookupMessage, t) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Marola.Pages.Icu qualified as Icu
import Marola.Pages.Language (Language)
import Marola.Pages.Language qualified as Language

type Catalog = Map Language (Map Text Text)

data Locale = Locale {catalog :: Catalog, language :: Language}

lookupMessage :: Catalog -> Language -> Text -> Maybe Text
lookupMessage c l key = Map.lookup l c >>= Map.lookup key

-- | The message for the key in the language, else the source language's, else the key itself. A
-- message that does not parse also gives the key: the bundler rejects those at build time.
t :: Locale -> Text -> Text
t loc key =
  case maybe (lookupMessage (catalog loc) Language.source key) Just (lookupMessage (catalog loc) (language loc) key) of
    Nothing -> key
    Just message -> either (const key) (`Icu.format` []) (Icu.parse message)
