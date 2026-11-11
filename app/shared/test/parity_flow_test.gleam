//// The old flow.js maths against golden.json. flow.js keeps its grid in
//// Float32Array, so the field values agree to about 1e-7, not to the bit.

import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import gleam/string
import marola/decoders
import marola/flow
import marola/mercator
import marola/ramp
import support

fn why(section: String, detail: String) -> String {
  "golden " <> section <> ": " <> detail
}

pub fn mercator_test() {
  let entry = {
    use name <- decode.field("fn", decode.string)
    use input <- decode.field("in", decoders.number())
    use out <- decode.field("out", decoders.number())
    decode.success(#(name, input, out))
  }
  use #(name, input, out) <- list.each(support.golden("mercator", entry))
  let got = case name {
    "x" -> mercator.x(input)
    "y" -> mercator.y(input)
    "lon_of" -> mercator.lon_of(input)
    "lat_of" -> mercator.lat_of(input)
    other -> panic as { "unknown mercator function " <> other }
  }
  assert support.close(got, out, 1.0e-12)
    as why("mercator", string.inspect(#(name, input)))
}

type Expected {
  Expected(
    x0: Float,
    x1: Float,
    y0: Float,
    y1: Float,
    cells: List(#(Int, flow.Cell)),
    samples: List(#(Float, Float, Option(flow.Cell))),
  )
}

fn cell_decoder() -> decode.Decoder(flow.Cell) {
  use u <- decode.field("u", decoders.number())
  use v <- decode.field("v", decoders.number())
  use m <- decode.field("m", decoders.number())
  use a <- decode.field("a", decoders.number())
  decode.success(flow.Cell(u:, v:, m:, a:))
}

fn expected_decoder() -> decode.Decoder(Expected) {
  let indexed = {
    use n <- decode.field("n", decode.int)
    use cell <- decode.then(cell_decoder())
    decode.success(#(n, cell))
  }
  let sample = {
    use x <- decode.field("x", decoders.number())
    use y <- decode.field("y", decoders.number())
    use out <- decode.field(
      "out",
      decode.optional(
        decode.list(decoders.number())
        |> decode.map(fn(values) {
          case values {
            [u, v, m, a] -> flow.Cell(u, v, m, a)
            _ -> panic as "a sample has four numbers"
          }
        }),
      ),
    )
    decode.success(#(x, y, out))
  }
  use x0 <- decode.field("x0", decoders.number())
  use x1 <- decode.field("x1", decoders.number())
  use y0 <- decode.field("y0", decoders.number())
  use y1 <- decode.field("y1", decoders.number())
  use cells <- decode.field("cells", decode.list(indexed))
  use samples <- decode.field("samples", decode.list(sample))
  decode.success(Expected(x0:, x1:, y0:, y1:, cells:, samples:))
}

fn cell_close(a: flow.Cell, b: flow.Cell) -> Bool {
  support.all_close([a.u, a.v, a.m, a.a], [b.u, b.v, b.m, b.a], 1.0e-5)
}

pub fn field_and_sample_test() {
  let reading = {
    use lon <- decode.field("lon", decoders.number())
    use lat <- decode.field("lat", decoders.number())
    use mag <- decode.field("mag", decoders.nullable_number())
    use dir <- decode.field("dir", decoders.nullable_number())
    decode.success(flow.Reading(lon:, lat:, mag:, dir:))
  }
  let entry = {
    use max <- decode.field("max", decoders.number())
    use points <- decode.field("points", decode.list(reading))
    use expected <- decode.field("field", decode.optional(expected_decoder()))
    decode.success(#(max, points, expected))
  }
  use #(max, points, expected) <- list.each(support.golden("field", entry))
  let label = string.inspect(points)
  case flow.build_field(points, max), expected {
    Error(Nil), option.None -> Nil
    Ok(field), option.Some(want) -> {
      assert support.all_close(
        [field.x0, field.x1, field.y0, field.y1],
        [want.x0, want.x1, want.y0, want.y1],
        1.0e-12,
      )
        as why("field bounds", label)
      use #(n, cell) <- list.each(want.cells)
      let assert Ok(got) = dict.get(field.cells, n)
      assert cell_close(got, cell)
        as why("field cell", label <> " " <> string.inspect(n))
      Nil
    }
    _, _ -> panic as why("field", "null does not match: " <> label)
  }
  case flow.build_field(points, max), expected {
    Ok(field), option.Some(want) -> {
      use #(x, y, out) <- list.each(want.samples)
      let label = string.inspect(#(x, y))
      case flow.sample(field, x, y), out {
        Error(Nil), option.None -> Nil
        Ok(got), option.Some(cell) -> {
          assert cell_close(got, cell) as why("sample", label)
        }
        _, _ -> panic as why("sample", "outside does not match: " <> label)
      }
    }
    _, _ -> Nil
  }
}

pub fn hex_rgb_test() {
  let entry = {
    use input <- decode.field("in", decode.string)
    use out <- decode.field("out", decode.list(decode.int))
    decode.success(#(input, out))
  }
  use #(input, out) <- list.each(support.golden("hex_rgb", entry))
  let #(r, g, b) = ramp.hex_rgb(input)
  assert [r, g, b] == out as why("hex_rgb", input)
}

pub fn ramp_pixels_test() {
  let entry = {
    use stops <- decode.field("stops", decode.list(decode.string))
    use out <- decode.field("out", decode.list(decode.int))
    decode.success(#(stops, out))
  }
  use #(stops, out) <- list.each(support.golden("ramp", entry))
  assert ramp.pixels(stops) == Ok(out) as why("ramp", string.inspect(stops))
}

pub fn ramp_needs_two_stops_test() {
  assert ramp.pixels([]) == Error(Nil)
  assert ramp.pixels(["#000000"]) == Error(Nil)
}
