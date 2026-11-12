-- | The Content-Security-Policy of the map page: one value, sent as an HTTP header by whatever
-- serves the page. @marola-server csp@ prints it into dist/csp.txt, and front/index.html's <meta>
-- must equal it without frame-ancestors (scripts/front_check.js).
--
-- The page loads every script and style from @'self'@. Two third parties answer it: OpenFreeMap
-- for the base map and NASA GIBS for the satellite layers. @data:@ and @blob:@ are schemes, not
-- origins: MapLibre decodes its sprite sheet through an image built from a blob.
module Marola.Csp (openfreemap, gibs, policy) where

import Data.Text (Text)
import Data.Text qualified as T

openfreemap, gibs :: Text
openfreemap = "tiles.openfreemap.org"
gibs = "gibs.earthdata.nasa.gov"

origins :: Text
origins = T.unwords (map ("https://" <>) [openfreemap, gibs])

-- | A header cannot carry a newline, so the directives join into one line.
policy :: Text
policy =
  T.intercalate
    "; "
    [ "default-src 'self'",
      "script-src 'self'",
      "style-src 'self'",
      "img-src 'self' data: blob: " <> origins,
      "connect-src 'self' " <> origins,
      "font-src 'self'",
      "worker-src 'self'",
      "object-src 'none'",
      "base-uri 'self'",
      "frame-ancestors 'none'"
    ]
