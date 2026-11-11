namespace Marola

/// Web Mercator in unit space (0..1 across the world), as flow.js draws in.
module Mercator =

    /// Latitude where the projection's log would reach infinity; stays finite.
    let private latLimit = 89.999999

    let x (lon: float) : float = (lon + 180.0) / 360.0

    let y (lat: float) : float =
        let clamped =
            if lat > latLimit then latLimit
            elif lat < -latLimit then -latLimit
            else lat

        let s = System.Math.Sin(clamped * System.Math.PI / 180.0)
        0.5 - System.Math.Log((1.0 + s) / (1.0 - s)) / (4.0 * System.Math.PI)

    let lonOf (x: float) : float = x * 360.0 - 180.0

    let latOf (y: float) : float =
        360.0 / System.Math.PI
        * System.Math.Atan(System.Math.Exp((1.0 - 2.0 * y) * System.Math.PI))
        - 90.0
