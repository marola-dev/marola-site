module Msg exposing (FetchError(..), Fold(..), Loaded(..), Msg(..))

import Area exposing (Area)
import Board exposing (Board)
import Dict exposing (Dict)
import Geo exposing (Point)
import Language exposing (Language)
import Layer exposing (Layer)
import Model exposing (DayEntry)
import Trails exposing (Trails)


{-| Why a request gave no data, as the footer words it (`Update.describe`).
-}
type FetchError
    = HttpError Int
    | NetworkError
    | BadUrl
    | BadData String


{-| A board file, or the news that its schema is newer than this page.
-}
type Loaded
    = Read Board
    | Newer Int


type Fold
    = LoreFold
    | BlurbFold


type Msg
    = CatalogLoaded Language (Result FetchError (Dict String String))
    | AreasLoaded (Result FetchError (List Area))
    | LatestLoaded String (Result FetchError (List DayEntry))
    | BoardLoaded String String String (Result FetchError Loaded)
    | TrailsFileLoaded String (Result FetchError Trails)
    | AreaPicked String
    | DayPicked String
      -- The slider's position: -1 is each beach at its own best hour.
    | HourMoved Int
      -- `pan` is true from the list and false from the map, where the beach is already in view.
    | BeachPicked String Bool
    | CardClosed
    | LayerPressed Layer
    | BeachesToggled
    | TrailsToggled
    | ListToggled
    | TrailPanelToggled
      -- `fit` is true from the panel, which names a route the map may not show.
    | TrailChosen Int Bool
    | NearPressed
    | Located (Result String Point)
    | FoldToggled Fold
    | SosToggled
    | SosClosed
    | LanguagePicked Language
    | SoundPressed
    | SoundFailed
      -- An event of the map named by `maplibre_ffi.mjs`: ready, error, click, beach, trail.
    | MapEvent String String
    | Ignored
