namespace Marola

/// One beach reading. `Dir` is the degrees the flow comes FROM (Open-Meteo's convention). A
/// reading without both numbers is left out.
type Reading =
    { Lon: float
      Lat: float
      Mag: float option
      Dir: float option }

/// A cell: `U` and `V` east and north in units of `Mag`, `M` is mag over max (0..1) and `A` is how
/// close the nearest beach is (0..1).
type FlowCell =
    { U: float
      V: float
      M: float
      A: float }

/// A `Flow.grid` by `Flow.grid` field in mercator space. `Cells` is row-major and never changes
/// after `buildField`.
type Field =
    { W: int
      H: int
      X0: float
      X1: float
      Y0: float
      Y1: float
      Max: float
      Cells: FlowCell array }

/// The wind and wave field of the flow layer, interpolated from the beaches' own readings (no
/// weather grid is fetched). A port of flow.js `buildField` and `sample`. flow.js keeps the grid
/// in Float32Array, so its values are rounded to 32 bits; these stay in 64 bits and differ by
/// about 1e-7.
module Flow =

    let private kmPerDeg = 111.32

    /// The field reaches this far past the outermost beach.
    let private padKm = 30.0

    /// It fades out over about this distance from the nearest one.
    let private reachKm = 18.0

    let grid = 96

    type private Vec =
        { X: float
          Y: float
          U: float
          V: float
          Mag: float }

    /// Inverse-distance weighting of every reading at one point.
    let private cell (vecs: Vec list) (px: float) (py: float) (max: float) : FlowCell =
        let sw, su, sv, sm, dmin =
            vecs
            |> List.fold
                (fun (sw, su, sv, sm, dmin) vec ->
                    let dx = px - vec.X
                    let dy = py - vec.Y
                    let d2 = dx * dx + dy * dy
                    let w = 1.0 / (d2 + 0.25)
                    sw + w, su + w * vec.U, sv + w * vec.V, sm + w * vec.Mag, min dmin d2)
                (0.0, 0.0, 0.0, 0.0, System.Double.MaxValue)

        { U = su / sw
          V = sv / sw
          M = min 1.0 (sm / sw / max)
          A = System.Math.Exp(0.0 - dmin / (reachKm * reachKm)) }

    let private field (pts: (float * float * float * float) list) (max: float) : Field =
        let count = float (List.length pts)
        let lat0 = (pts |> List.fold (fun sum (_, lat, _, _) -> sum + lat) 0.0) / count
        let kx = kmPerDeg * System.Math.Cos(lat0 * System.Math.PI / 180.0)
        let ky = kmPerDeg
        let lons = pts |> List.map (fun (lon, _, _, _) -> lon)
        let lats = pts |> List.map (fun (_, lat, _, _) -> lat)
        let minLon = List.fold min System.Double.MaxValue lons - padKm / kx
        let maxLon = List.fold Operators.max -System.Double.MaxValue lons + padKm / kx
        let minLat = List.fold min System.Double.MaxValue lats - padKm / ky
        let maxLat = List.fold Operators.max -System.Double.MaxValue lats + padKm / ky
        let x0 = Mercator.x minLon
        let x1 = Mercator.x maxLon
        let y0 = Mercator.y maxLat
        let y1 = Mercator.y minLat

        let vecs =
            pts
            |> List.map (fun (lon, lat, mag, dir) ->
                // The board says where the flow comes from; particles go the other way.
                let toward = (dir + 180.0) * System.Math.PI / 180.0

                { X = lon * kx
                  Y = lat * ky
                  U = System.Math.Sin toward * mag
                  V = System.Math.Cos toward * mag
                  Mag = mag })

        let g = float grid

        let cells =
            Array.init (grid * grid) (fun n ->
                let j = n / grid
                let i = n % grid
                let lat = Mercator.latOf (y0 + (y1 - y0) * (float j + 0.5) / g)
                let lon = Mercator.lonOf (x0 + (x1 - x0) * (float i + 0.5) / g)
                cell vecs (lon * kx) (lat * ky) max)

        { W = grid
          H = grid
          X0 = x0
          X1 = x1
          Y0 = y0
          Y1 = y1
          Max = max
          Cells = cells }

    /// `None` when no reading has both numbers.
    let buildField (readings: Reading list) (max: float) : Field option =
        let pts =
            readings
            |> List.choose (fun r ->
                match r.Mag, r.Dir with
                | Some mag, Some dir -> Some(r.Lon, r.Lat, mag, dir)
                | _ -> None)

        match pts with
        | [] -> None
        | _ -> Some(field pts max)

    /// Bilinear sample at a mercator point, or `None` outside the field.
    let sample (f: Field) (x: float) (y: float) : FlowCell option =
        let w = float f.W
        let h = float f.H
        let gx = (x - f.X0) / (f.X1 - f.X0) * w - 0.5
        let gy = (y - f.Y0) / (f.Y1 - f.Y0) * h - 0.5

        if gx >= -0.5 && gy >= -0.5 && gx <= w - 0.5 && gy <= h - 0.5 then
            let i0 = Operators.max 0 (min (f.W - 1) (int (System.Math.Floor gx)))
            let j0 = Operators.max 0 (min (f.H - 1) (int (System.Math.Floor gy)))
            let i1 = min (f.W - 1) (i0 + 1)
            let j1 = min (f.H - 1) (j0 + 1)
            let clamp01 v = Operators.max 0.0 (min 1.0 v)
            let tx = clamp01 (gx - float i0)
            let ty = clamp01 (gy - float j0)

            let at (pick: FlowCell -> float) =
                let get j i = pick f.Cells.[j * f.W + i]
                let a = get j0 i0 * (1.0 - tx) + get j0 i1 * tx
                let b = get j1 i0 * (1.0 - tx) + get j1 i1 * tx
                a * (1.0 - ty) + b * ty

            Some
                { U = at (fun c -> c.U)
                  V = at (fun c -> c.V)
                  M = at (fun c -> c.M)
                  A = at (fun c -> c.A) }
        else
            None
