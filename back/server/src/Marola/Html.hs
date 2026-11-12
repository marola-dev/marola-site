-- | Links that reach the page: @safeHref@.
module Marola.Html (safeHref) where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Text (Text)
import Data.Text qualified as T

isLetter :: Char -> Bool
isLetter c = isAsciiUpper c || isAsciiLower c

validScheme :: Text -> Bool
validScheme s = case T.uncons s of
  Just (c, _) -> isLetter c && T.all (\x -> isLetter x || isDigit x || x `elem` ("+-." :: String)) s
  Nothing -> False

isControl' :: Char -> Bool
isControl' c = c < '\x20' || (c >= '\x7f' && c <= '\x9f')

-- | A link a page may put in an @href@: only @https:@, @http:@ and @mailto:@. It reads the URL the
-- way a browser does, which drops tab and newline anywhere and the controls and spaces around it,
-- so "java\tscript:..." cannot slip through. The result still needs attribute escaping.
safeHref :: Text -> Maybe Text
safeHref url =
  let cleaned = T.dropAround (<= '\x20') (T.filter (`notElem` ("\t\n\r" :: String)) url)
      (scheme, rest) = T.breakOn ":" cleaned
   in if not (T.null rest)
        && T.length rest > 1
        && validScheme scheme
        && T.toLower scheme `elem` ["https", "http", "mailto"]
        && not (T.any isControl' cleaned)
        then Just cleaned
        else Nothing
