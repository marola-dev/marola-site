-- | Lengths and prefixes counted in UTF-16 code units, as JavaScript's @length@ counts them: the
-- field limits of the API are documented in those units (OpenAPI, "Submission").
module Marola.Utf16 (len, take) where

import Data.Char (ord)
import Data.Text (Text)
import Data.Text qualified as T
import Prelude hiding (take)

units :: Char -> Int
units c = if ord c > 0xFFFF then 2 else 1

len :: Text -> Int
len = T.foldl' (\n c -> n + units c) 0

-- | The longest prefix of at most @n@ units. A surrogate pair cut in half is dropped whole, never
-- left as a lone high surrogate.
take :: Int -> Text -> Text
take n t = T.take (go 0 0 (T.unpack t)) t
  where
    go !used !chars = \case
      (c : cs) | used + units c <= n -> go (used + units c) (chars + 1) cs
      _ -> chars
