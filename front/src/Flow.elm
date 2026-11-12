module Flow exposing (Cell, Field, Reading, buildField, grid)

{-| The wind and wave field of the flow layer, interpolated from the beaches' own readings (no
weather grid is fetched). A port of flow.js `buildField`; flow.js keeps Float32Array values,
these stay 64-bit and differ by about 1e-7.
-}

import Array exposing (Array)
import Mercator


{-| `dir` is the degrees the flow comes FROM (Open-Meteo's convention).
-}
type alias Reading =
    { lon : Float, lat : Float, mag : Maybe Float, dir : Maybe Float }


{-| `u` and `v` east and north in units of `mag`, `m` is mag over max, `a` how close the nearest
beach is.
-}
type alias Cell =
    { u : Float, v : Float, m : Float, a : Float }


type alias Field =
    { w : Int, h : Int, x0 : Float, x1 : Float, y0 : Float, y1 : Float, max : Float, cells : Array Cell }


kmPerDeg : Float
kmPerDeg =
    111.32


padKm : Float
padKm =
    30


reachKm : Float
reachKm =
    18


grid : Int
grid =
    96


type alias Vec =
    { x : Float, y : Float, u : Float, v : Float, mag : Float }


maxFloat : Float
maxFloat =
    1.7976931348623157e308


cell : List Vec -> Float -> Float -> Float -> Cell
cell vecs px py top =
    let
        step vec ( ( sw, su ), ( sv, sm ), dmin ) =
            let
                dx =
                    px - vec.x

                dy =
                    py - vec.y

                d2 =
                    dx * dx + dy * dy

                w =
                    1 / (d2 + 0.25)
            in
            ( ( sw + w, su + w * vec.u ), ( sv + w * vec.v, sm + w * vec.mag ), min dmin d2 )

        ( ( sw1, su1 ), ( sv1, sm1 ), dmin1 ) =
            List.foldl step ( ( 0, 0 ), ( 0, 0 ), maxFloat ) vecs
    in
    { u = su1 / sw1
    , v = sv1 / sw1
    , m = min 1 (sm1 / sw1 / top)
    , a = Basics.e ^ (0 - dmin1 / (reachKm * reachKm))
    }


field : List ( ( Float, Float ), ( Float, Float ) ) -> Float -> Field
field pts top =
    let
        count =
            toFloat (List.length pts)

        lons =
            List.map (Tuple.first >> Tuple.first) pts

        lats =
            List.map (Tuple.first >> Tuple.second) pts

        lat0 =
            List.foldl (+) 0 lats / count

        kx =
            kmPerDeg * cos (lat0 * pi / 180)

        ky =
            kmPerDeg

        minLon =
            List.foldl min maxFloat lons - padKm / kx

        maxLon =
            List.foldl max -maxFloat lons + padKm / kx

        minLat =
            List.foldl min maxFloat lats - padKm / ky

        maxLat =
            List.foldl max -maxFloat lats + padKm / ky

        x0 =
            Mercator.x minLon

        x1 =
            Mercator.x maxLon

        y0 =
            Mercator.y maxLat

        y1 =
            Mercator.y minLat

        vecs =
            pts
                |> List.map
                    (\( ( lon, lat ), ( mag, dir ) ) ->
                        let
                            -- The board says where the flow comes from; particles go the other way.
                            toward =
                                (dir + 180) * pi / 180
                        in
                        { x = lon * kx, y = lat * ky, u = sin toward * mag, v = cos toward * mag, mag = mag }
                    )

        g =
            toFloat grid

        cells =
            Array.initialize (grid * grid)
                (\n ->
                    let
                        j =
                            n // grid

                        i =
                            modBy grid n

                        lat =
                            Mercator.latOf (y0 + (y1 - y0) * (toFloat j + 0.5) / g)

                        lon =
                            Mercator.lonOf (x0 + (x1 - x0) * (toFloat i + 0.5) / g)
                    in
                    cell vecs (lon * kx) (lat * ky) top
                )
    in
    { w = grid, h = grid, x0 = x0, x1 = x1, y0 = y0, y1 = y1, max = top, cells = cells }


{-| `Nothing` when no reading has both numbers.
-}
buildField : List Reading -> Float -> Maybe Field
buildField readings top =
    let
        pts =
            List.filterMap
                (\r ->
                    case ( r.mag, r.dir ) of
                        ( Just mag, Just dir ) ->
                            Just ( ( r.lon, r.lat ), ( mag, dir ) )

                        _ ->
                            Nothing
                )
                readings
    in
    if List.isEmpty pts then
        Nothing

    else
        Just (field pts top)
