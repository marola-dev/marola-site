namespace Marola

/// The list's two orders. The old `ranked()` wrote `_km` into the board; here the distance
/// travels beside the beach and the board stays as it was.
module Rank =

    /// Nearest first, each with its distance in km.
    let byDistance (beaches: Beach list) (here: Point) : (Beach * float) list =
        beaches
        |> List.map (fun b -> b, Geo.haversineKm here { Lat = b.Lat; Lon = b.Lon })
        |> List.sortWith (fun (_, a) (_, b) -> compare a b)

    /// Best score first at the hour on show; a beach dark then goes last.
    let byScore (beaches: Beach list) (selection: Selection) : Beach list =
        let score b =
            match Beach.shown b selection with
            | Some s -> s.Score
            | None -> -1

        beaches |> List.sortWith (fun a b -> compare (score b) (score a))
