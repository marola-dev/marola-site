-- | Fixed-window counters per key, in memory: a restart resets them.
module Marola.Server.RateLimit (Window, newWindow, take) where

import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime)
import Prelude hiding (take)

data Window k = Window
  { permits :: Int,
    span :: NominalDiffTime,
    table :: IORef (Map.Map k (UTCTime, Int))
  }

newWindow :: Int -> NominalDiffTime -> IO (Window k)
newWindow p s = Window p s <$> newIORef Map.empty

-- | Takes @cost@ units at @now@. 'Right' when they fit; 'Left' the seconds until the window ends.
take :: (Ord k) => Window k -> k -> Int -> UTCTime -> IO (Either Int ())
take w key cost now = atomicModifyIORef' w.table $ \m ->
  let m' = if Map.size m > 10000 then Map.filter (\(s, _) -> diffUTCTime now s < w.span) m else m
      (start, used) = case Map.lookup key m' of
        Just (s, u) | diffUTCTime now s < w.span -> (s, u)
        _ -> (now, 0)
   in if used + cost > w.permits
        then (Map.insert key (start, used) m', Left (max 1 (ceiling (w.span - diffUTCTime now start))))
        else (Map.insert key (start, used + cost) m', Right ())
