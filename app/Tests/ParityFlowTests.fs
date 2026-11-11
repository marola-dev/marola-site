/// The old flow.js maths against golden.json. flow.js keeps its grid in Float32Array, so the
/// field values agree to about 1e-7, not to the bit.
module Marola.Tests.ParityFlowTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Thoth.Json.Core
open Marola
open Marola.Tests.Support

let private why (section: string) (detail: string) : string = "golden " + section + ": " + detail

type private Expected =
    { X0: float
      X1: float
      Y0: float
      Y1: float
      Cells: (int * FlowCell) list
      Samples: (float * float * FlowCell option) list }

let private cellDecoder: Decoder<FlowCell> =
    Decode.object (fun get ->
        { U = get.Required.Field "u" Decoders.number
          V = get.Required.Field "v" Decoders.number
          M = get.Required.Field "m" Decoders.number
          A = get.Required.Field "a" Decoders.number })

let private expectedDecoder: Decoder<Expected> =
    let indexed =
        Decode.object (fun get -> get.Required.Field "n" Decoders.int, get.Required.Raw cellDecoder)

    let sampleValue =
        Decode.list Decoders.number
        |> Decode.andThen (fun values ->
            match values with
            | [ u; v; m; a ] -> Decode.succeed { U = u; V = v; M = m; A = a }
            | _ -> Decode.fail "a sample has four numbers")

    let sample =
        Decode.object (fun get ->
            get.Required.Field "x" Decoders.number,
            get.Required.Field "y" Decoders.number,
            get.Required.Field "out" (Decode.lossyOption sampleValue))

    Decode.object (fun get ->
        { X0 = get.Required.Field "x0" Decoders.number
          X1 = get.Required.Field "x1" Decoders.number
          Y0 = get.Required.Field "y0" Decoders.number
          Y1 = get.Required.Field "y1" Decoders.number
          Cells = get.Required.Field "cells" (Decode.list indexed)
          Samples = get.Required.Field "samples" (Decode.list sample) })

let private cellClose (a: FlowCell) (b: FlowCell) : bool =
    allClose [ a.U; a.V; a.M; a.A ] [ b.U; b.V; b.M; b.A ] 1.0e-5

let tests =
    testList
        "parity flow"
        [ testCase "mercator"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "fn" Decode.string,
                      get.Required.Field "in" Decoders.number,
                      get.Required.Field "out" Decoders.number)

              for name, input, out in golden "mercator" entry do
                  let got =
                      match name with
                      | "x" -> Mercator.x input
                      | "y" -> Mercator.y input
                      | "lon_of" -> Mercator.lonOf input
                      | "lat_of" -> Mercator.latOf input
                      | other -> failwith ("unknown mercator function " + other)

                  Expect.isTrue (close got out 1.0e-12) (why "mercator" (string (name, input)))

          testCase "field and sample"
          <| fun () ->
              let reading =
                  Decode.object (fun get ->
                      { Lon = get.Required.Field "lon" Decoders.number
                        Lat = get.Required.Field "lat" Decoders.number
                        Mag = get.Required.Field "mag" Decoders.nullableNumber
                        Dir = get.Required.Field "dir" Decoders.nullableNumber })

              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "max" Decoders.number,
                      get.Required.Field "points" (Decode.list reading),
                      get.Required.Field "field" (Decode.lossyOption expectedDecoder))

              for max, points, expected in golden "field" entry do
                  let label = string points

                  match Flow.buildField points max, expected with
                  | None, None -> ()
                  | Some field, Some want ->
                      Expect.isTrue
                          (allClose
                              [ field.X0; field.X1; field.Y0; field.Y1 ]
                              [ want.X0; want.X1; want.Y0; want.Y1 ]
                              1.0e-12)
                          (why "field bounds" label)

                      for n, cell in want.Cells do
                          Expect.isTrue (cellClose field.Cells.[n] cell) (why "field cell" (label + " " + string n))

                      for x, y, out in want.Samples do
                          let sampleLabel = string (x, y)

                          match Flow.sample field x y, out with
                          | None, None -> ()
                          | Some got, Some cell -> Expect.isTrue (cellClose got cell) (why "sample" sampleLabel)
                          | _ -> failwith (why "sample" ("outside does not match: " + sampleLabel))
                  | _ -> failwith (why "field" ("null does not match: " + label))

          testCase "hexRgb"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "in" Decode.string, get.Required.Field "out" (Decode.list Decoders.int))

              for input, out in golden "hex_rgb" entry do
                  let r, g, b = Ramp.hexRgb input
                  Expect.equal [ r; g; b ] out (why "hex_rgb" input)

          testCase "ramp pixels"
          <| fun () ->
              let entry =
                  Decode.object (fun get ->
                      get.Required.Field "stops" (Decode.list Decode.string),
                      get.Required.Field "out" (Decode.list Decoders.int))

              for stops, out in golden "ramp" entry do
                  Expect.equal (Ramp.pixels stops |> Option.map List.ofArray) (Some out) (why "ramp" (string stops))

          testCase "a ramp needs two stops"
          <| fun () ->
              Expect.equal (Ramp.pixels []) None "none"
              Expect.equal (Ramp.pixels [ "#000000" ]) None "one" ]
