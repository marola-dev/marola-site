module Effect exposing (Camera(..), Effect(..))

{-| What `update` asks of the world. A value, not an action: the tests read it, and `Main` is the
one place that carries it out through the ports.
-}

import Language exposing (Language)


type Camera
    = Jump Float Float Float
      -- west, south, east, north, padding, max zoom (a lone beach must not fill the screen), instant
    | Fit Float Float Float Float Int Int Bool
    | Pan Float Float
      -- The Pacific, whose Nino 3.4 box needs a zoom the area's minimum forbids.
    | Pacific Bool
    | MinZoom Int


type Effect
    = FetchCatalog Language
    | FetchAreas
    | FetchLatest String
    | FetchBoard String String String
    | FetchTrails String
    | ReplaceUrl String String
    | SetDocument String String
    | StoreLanguage Language
    | InitMap Float Float
      -- The markers, raster and visibility of the map, as one JSON text.
    | SyncMap String
      -- The GeoJSON of the trail routes.
    | SetTrails String
      -- The flow layer's field as JSON, or `null` for none.
    | SetFlow String
    | MoveCamera Camera
    | Locate
    | Alert String
    | Focus String
