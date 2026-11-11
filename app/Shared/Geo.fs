namespace Marola

/// Points on the earth.
type Point = { Lat: float; Lon: float }

/// Great-circle distance and compass points.
module Geo =

    let private earthRadiusKm = 6371.0

    let private radians (degrees: float) : float = degrees * System.Math.PI / 180.0

    /// The great-circle distance in km. The operations keep the order of app.js `haversineKm`, so
    /// both agree to the last digits.
    let haversineKm (a: Point) (b: Point) : float =
        let dLat = radians (b.Lat - a.Lat)
        let dLon = radians (b.Lon - a.Lon)
        let la1 = radians a.Lat
        let la2 = radians b.Lat

        let h =
            System.Math.Sin(dLat / 2.0) * System.Math.Sin(dLat / 2.0)
            + System.Math.Cos la1
              * System.Math.Cos la2
              * System.Math.Sin(dLon / 2.0)
              * System.Math.Sin(dLon / 2.0)

        // Rounding can push h just past 1 for antipodes; asin would give NaN there.
        let root = if h < 0.0 then 0.0 else System.Math.Sqrt(min h 1.0)
        2.0 * earthRadiusKm * System.Math.Asin root

    let private compassPoints = [| "n"; "ne"; "e"; "se"; "s"; "sw"; "w"; "nw" |]

    /// The catalog key suffix (`dir.<this>`) of a bearing in degrees, to the nearest of eight points.
    let compassKey (degrees: float) : string =
        let index = int (System.Math.Floor(degrees / 45.0 + 0.5))
        compassPoints.[((index % 8) + 8) % 8]
