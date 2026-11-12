-- | The English head of the map page. Vite writes one @index.html@, in pt-BR; the server sends
-- @index.en.html@ for @/?lang=en@ (Marola.Server.Files), so a crawler reads an English title,
-- description and @lang@, and a canonical that is that address instead of the pt-BR one, which
-- would make the hreflang pair point at a duplicate.
module Marola.Pages.MapPage (english, descriptionPt, descriptionEn) where

import Data.Text (Text)
import Data.Text qualified as T
import Marola.Pages.I18n (Catalog, lookupMessage)
import Marola.Pages.Language (Language (..))

-- | The text of front/index.html's description; the English is its translation.
descriptionPt, descriptionEn :: Text
descriptionPt = "Todas as praias da região ordenadas pelas condições de hoje e de amanhã: mar, vento, ondas, maré, qualidade da água e águas-vivas. Dados abertos e sem cookies."
descriptionEn = "Every beach in the area ranked by today's and tomorrow's conditions: sea, wind, waves, tide, water quality and jellyfish. Open data, no cookies."

-- | Each pt-BR string must be in the page, or the build fails: a change to front/index.html that
-- this list does not follow would otherwise ship a half-translated head.
english :: Catalog -> Text -> Either Text Text
english catalog page = do
  titlePt <- message PtBr
  titleEn <- message En
  let swaps =
        [ ("<html lang=\"pt-BR\">", "<html lang=\"en\">"),
          (titlePt, titleEn),
          (descriptionPt, descriptionEn),
          ("<link rel=\"canonical\" href=\"https://marola.dev/\">", "<link rel=\"canonical\" href=\"https://marola.dev/?lang=en\">"),
          ("<meta property=\"og:url\" content=\"https://marola.dev/\">", "<meta property=\"og:url\" content=\"https://marola.dev/?lang=en\">"),
          ("<meta property=\"og:locale\" content=\"pt_BR\">", "<meta property=\"og:locale\" content=\"en_US\">"),
          ("<meta property=\"og:locale:alternate\" content=\"en_US\">", "<meta property=\"og:locale:alternate\" content=\"pt_BR\">")
        ]
  foldl (\acc (from, to) -> acc >>= swap from to) (Right page) swaps
  where
    message l = maybe (Left ("map page: no title.map in the " <> T.pack (show l) <> " catalog")) Right (lookupMessage catalog l "title.map")
    swap from to txt
      | from `T.isInfixOf` txt = Right (T.replace from to txt)
      | otherwise = Left ("map page: front/index.html no longer has " <> T.take 80 from)
