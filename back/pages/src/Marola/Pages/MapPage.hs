-- | The non-pt-BR heads of the map page. Vite writes one @index.html@, in pt-BR; the server sends
-- @index.<tag>.html@ for @/?lang=<tag>@ (Marola.Server.Files), so a crawler reads a head in that
-- language, and a canonical that is that address instead of the pt-BR one, which would make the
-- hreflang group point at a duplicate.
module Marola.Pages.MapPage (variants, descriptionPt, descriptionEn, descriptionJa, descriptionZh) where

import Data.Text (Text)
import Data.Text qualified as T
import Marola.Pages.I18n (Catalog, lookupMessage)
import Marola.Pages.Language (Language (..))
import Marola.Pages.Language qualified as Language

-- | The text of front/index.html's description; the rest are its translations.
descriptionPt, descriptionEn, descriptionJa, descriptionZh :: Text
descriptionPt = "Todas as praias da região ordenadas pelas condições de hoje e de amanhã: mar, vento, ondas, maré, qualidade da água e águas-vivas. Dados abertos e sem cookies."
descriptionEn = "Every beach in the area ranked by today's and tomorrow's conditions: sea, wind, waves, tide, water quality and jellyfish. Open data, no cookies."
descriptionJa = "今日と明日の海況で並べた地域のすべてのビーチ: 海、風、波、潮位、水質、クラゲ。公開データで、Cookieなし。"
descriptionZh = "依今天與明天的海況排序的區域所有海灘: 海況、風、浪、潮汐、水質與水母。公開資料，無 Cookie。"

description :: Language -> Text
description = \case
  PtBr -> descriptionPt
  En -> descriptionEn
  Ja -> descriptionJa
  ZhHant -> descriptionZh

-- | @/?lang=<tag>@ of a variant, the tag of a language, for the canonical and the @og:url@.
queryOf :: Language -> Text
queryOf l = "?lang=" <> Language.tag l

-- | The og:locale of a language.
ogLocale :: Language -> Text
ogLocale = \case
  PtBr -> "pt_BR"
  En -> "en_US"
  Ja -> "ja_JP"
  ZhHant -> "zh_Hant"

-- | Each pt-BR string must be in the page, or the build fails: a change to front/index.html that
-- this list does not follow would otherwise ship a half-translated head. One pass per non-pt-BR
-- language; the other og:locale alternates stay as they are, and a crawler that wants them finds
-- the static pages' heads, which carry the full set.
variants :: Catalog -> Text -> Either Text [(Language, Text)]
variants catalog page = mapM one [En, Ja, ZhHant]
  where
    one l = do
      titlePt <- message PtBr
      titleL <- message l
      let swaps =
            [ ("<html lang=\"pt-BR\">", "<html lang=\"" <> Language.tag l <> "\">"),
              (titlePt, titleL),
              (descriptionPt, description l),
              ("<link rel=\"canonical\" href=\"https://marola.dev/\">", "<link rel=\"canonical\" href=\"https://marola.dev/" <> queryOf l <> "\">"),
              ("<meta property=\"og:url\" content=\"https://marola.dev/\">", "<meta property=\"og:url\" content=\"https://marola.dev/" <> queryOf l <> "\">"),
              ("<meta property=\"og:locale\" content=\"pt_BR\">", "<meta property=\"og:locale\" content=\"" <> ogLocale l <> "\">")
            ]
      foldl (\acc (from, to) -> acc >>= swap from to) (Right page) swaps >>= \txt -> pure (l, txt)
    message l = maybe (Left ("map page: no title.map in the " <> T.pack (show l) <> " catalog")) Right (lookupMessage catalog l "title.map")
    swap from to txt
      | from `T.isInfixOf` txt = Right (T.replace from to txt)
      | otherwise = Left ("map page: front/index.html no longer has " <> T.take 80 from)
