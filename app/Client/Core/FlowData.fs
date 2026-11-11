namespace Marola.Client

open Marola

/// The flow layer's data: the wind or wave field between the beaches, at the hour on the slider.
/// The field is `Flow`'s; this turns it into the flat arrays `flow_layer_ffi.mjs` samples every frame.
module FlowData =

    /// The top of the colour ramp: km/h of wind, metres of wave.
    let private maxOf (layer: Layer) : float =
        match layer with
        | Layer.Wind -> 40.0
        | _ -> 3.0

    let private readings (model: Model) (layer: Layer) : Reading list =
        Model.beaches model
        |> List.choose (fun b ->
            Beach.hourEntry b (Beach.shown b model.Selection)
            // The directions are the board's, taken at the best hour.
            |> Option.map (fun entry ->
                match layer with
                | Layer.Wind ->
                    { Lon = b.Lon
                      Lat = b.Lat
                      Mag = entry.WindKmh
                      Dir = b.Sea.WindDirDeg }
                | _ ->
                    { Lon = b.Lon
                      Lat = b.Lat
                      Mag = entry.WaveM
                      Dir = b.Sea.WaveDirDeg }))

    let private rounded (values: float seq) : Json =
        JArr(values |> Seq.map (fun v -> JNum(System.Math.Round(v, 4))) |> List.ofSeq)

    let private ramp (layer: Layer) : string list =
        match layer with
        | Layer.Wind -> Config.windRamp
        | _ -> Config.waveRamp

    /// `null` when the layer is neither wind nor waves, or no beach has both numbers.
    let json (model: Model) : string =
        match model.Layer with
        | Layer.Wind
        | Layer.Waves ->
            match Flow.buildField (readings model model.Layer) (maxOf model.Layer) with
            | None -> "null"
            | Some field ->
                let cells = field.Cells

                JObj
                    [ "kind", JStr(Layer.key model.Layer)
                      "w", JInt field.W
                      "h", JInt field.H
                      "x0", JNum field.X0
                      "x1", JNum field.X1
                      "y0", JNum field.Y0
                      "y1", JNum field.Y1
                      "u", rounded (cells |> Seq.map (fun c -> c.U))
                      "v", rounded (cells |> Seq.map (fun c -> c.V))
                      "m", rounded (cells |> Seq.map (fun c -> c.M))
                      "a", rounded (cells |> Seq.map (fun c -> c.A))
                      "ramp", JArr(ramp model.Layer |> List.map JStr) ]
                |> Json.render
        | _ -> "null"
