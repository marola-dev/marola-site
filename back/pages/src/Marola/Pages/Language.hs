-- | The two languages of the page (MIP-0054 5.5).
module Marola.Pages.Language (Language (..), source, allLanguages, tag) where

import Data.Text (Text)

data Language = PtBr | En
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The language of the source text: a message missing elsewhere falls back to it.
source :: Language
source = PtBr

allLanguages :: [Language]
allLanguages = [PtBr, En]

tag :: Language -> Text
tag PtBr = "pt-BR"
tag En = "en"
