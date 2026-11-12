-- | The Content-Security-Policy of the map page: one value, sent as an HTTP header by whatever
-- serves the page. @marola-server csp@ prints it into dist/csp.txt, and front/index.html's <meta>
-- must equal it without frame-ancestors (scripts/front_check.js).
--
-- The page loads every script and style from @'self'@, and so the base map: its style, glyphs and
-- tiles are the site's own files (docs/adr/0006-self-hosted-basemap.md). One third party answers
-- the page, NASA GIBS for the satellite layers, and Spotify's player is the one frame. @data:@ and
-- @blob:@ are schemes, not origins: MapLibre builds its images and its worker's transfers from them.
module Marola.Csp (gibs, spotify, policy) where

import Data.Text (Text)
import Data.Text qualified as T

gibs, spotify :: Text
gibs = "gibs.earthdata.nasa.gov"

-- | The playlist player, an iframe the map page loads only when the visitor opens it.
spotify = "open.spotify.com"

origins :: Text
origins = "https://" <> gibs

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
      "frame-src https://" <> spotify,
      "object-src 'none'",
      "base-uri 'self'",
      "frame-ancestors 'none'"
    ]
