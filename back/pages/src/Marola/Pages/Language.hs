-- | The four languages of the site (MIP-0054 5.5): pt-BR is the source the owner manages, en is
-- the ASD-STE100 pass after it, and ja and zh-Hant are the LLM passes.
module Marola.Pages.Language (Language (..), source, allLanguages, tag) where

import Data.Text (Text)

data Language = PtBr | En | Ja | ZhHant
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The language of the source text: a message missing elsewhere falls back to it.
source :: Language
source = PtBr

allLanguages :: [Language]
allLanguages = [PtBr, En, Ja, ZhHant]

tag :: Language -> Text
tag PtBr = "pt-BR"
tag En = "en"
tag Ja = "ja"
tag ZhHant = "zh-Hant"
