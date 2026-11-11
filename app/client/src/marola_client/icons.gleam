//// The page's line icons: Lucide's shapes (ISC, `vendor/icons/LICENSE.lucide`
//// in the old page), except the jellyfish, drawn in the same 24 px, round-cap
//// style because Lucide has none. Every icon is decoration: `aria-hidden`.

import gleam/int
import gleam/list
import marola_client/dom.{type Dom}

type Shape {
  Path(String)
  Circle(Int, Int, Int)
  Rect(Int, Int, Int, Int, Int)
}

fn shapes(name: String) -> List(Shape) {
  case name {
    "wind" -> [
      Path("M12.8 19.6A2 2 0 1 0 14 16H2"),
      Path("M17.5 8a2.5 2.5 0 1 1 2 4H2"),
      Path("M9.8 4.4A2 2 0 1 1 11 8H2"),
    ]
    "thermometer" -> [Path("M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z")]
    "waves" -> [
      Path("M2 6q2.5 2 5 0t5 0 5 0 5 0"),
      Path("M2 12q2.5 2 5 0t5 0 5 0 5 0"),
      Path("M2 18q2.5 2 5 0t5 0 5 0 5 0"),
    ]
    "jellyfish" -> [
      Path("M4 12a8 8 0 0 1 16 0Z"),
      Path("M8 12v3a2 2 0 0 1-1 2v2"),
      Path("M12 12v9"),
      Path("M16 12v3a2 2 0 0 0 1 2v2"),
    ]
    "fish" -> [
      Path(
        "M6.5 12c.94-3.46 4.94-6 8.5-6 3.56 0 6.06 2.54 7 6-.94 3.47-3.44 6-7 6s-7.56-2.53-8.5-6Z",
      ),
      Path("M18 12v.5"),
      Path("M16 17.93a9.77 9.77 0 0 1 0-11.86"),
      Path(
        "M7 10.67C7 8 5.58 5.97 2.73 5.5c-1 1.5-1 5 .23 6.5-1.24 1.5-1.24 5-.23 6.5C5.58 18.03 7 16 7 13.33",
      ),
    ]
    "footprints" -> [
      Path(
        "M4 16v-2.38C4 11.5 2.97 10.5 3 8c.03-2.72 1.49-6 4.5-6C9.37 2 10 3.8 10 5.5c0 3.11-2 5.66-2 8.68V16a2 2 0 1 1-4 0Z",
      ),
      Path(
        "M20 20v-2.38c0-2.12 1.03-3.12 1-5.62-.03-2.72-1.49-6-4.5-6C14.63 6 14 7.8 14 9.5c0 3.11 2 5.66 2 8.68V20a2 2 0 1 0 4 0Z",
      ),
    ]
    "parking" -> [Circle(12, 12, 10), Path("M9 17V7h4a3 3 0 0 1 0 6H9")]
    "toilets" -> [
      Path(
        "M7 12h13a1 1 0 0 1 1 1 5 5 0 0 1-5 5h-.598a.5.5 0 0 0-.424.765l1.544 2.47a.5.5 0 0 1-.424.765H5.402a.5.5 0 0 1-.424-.765L7 18",
      ),
      Path("M8 18a5 5 0 0 1-5-5V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v8"),
    ]
    "shower" -> [
      Path("m4 4 2.5 2.5"),
      Path("M13.5 6.5a4.95 4.95 0 0 0-7 7"),
      Path("M15 5 5 15"),
      Path("M14 17v.01"),
      Path("M10 16v.01"),
      Path("M13 13v.01"),
      Path("M16 10v.01"),
    ]
    "lifeguard" -> [
      Circle(12, 12, 10),
      Path("m4.93 4.93 4.24 4.24"),
      Path("m14.83 9.17 4.24-4.24"),
      Path("m14.83 14.83 4.24 4.24"),
      Path("m9.17 14.83-4.24 4.24"),
      Circle(12, 12, 4),
    ]
    "book" -> [
      Path("M12 5v16"),
      Path(
        "M20 19a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2h-4a5 5 0 0 0-4 2 5 5 0 0 0-4-2H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4a5 5 0 0 1 4 2 5 5 0 0 1 4-2z",
      ),
    ]
    "pin" -> [
      Path(
        "M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0",
      ),
      Circle(12, 10, 3),
    ]
    "droplet" -> [
      Path(
        "M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z",
      ),
    ]
    "cloud" -> [Path("M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z")]
    "pulse" -> [
      Path(
        "M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2",
      ),
    ]
    "globe" -> [
      Circle(12, 12, 10),
      Path("M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"),
      Path("M2 12h20"),
    ]
    "mountain" -> [Path("m8 3 4 8 5-5 5 15H2L8 3z")]
    "instagram" -> [
      Rect(2, 2, 20, 20, 5),
      Circle(12, 12, 4),
      Path("M17.5 6.5h.01"),
    ]
    "locate" -> [Circle(12, 12, 7), Path("M2 12h3M19 12h3M12 2v3M12 19v3")]
    "sound" -> [
      Path(
        "M11 4.7a.7.7 0 0 0-1.2-.5L6.4 7.6a1.4 1.4 0 0 1-1 .4H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.4a1.4 1.4 0 0 1 1 .4l3.4 3.4a.7.7 0 0 0 1.2-.5z",
      ),
      Path("M16 9a5 5 0 0 1 0 6"),
      Path("M19.4 18.4a9 9 0 0 0 0-12.8"),
    ]
    "list" -> [Path("M3 5h.01M3 12h.01M3 19h.01M8 5h13M8 12h13M8 19h13")]
    "phone" -> [
      Path(
        "M13.832 16.568a1 1 0 0 0 1.213-.303l.355-.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2A18 18 0 0 1 2 4a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3a2 2 0 0 1-.8 1.6l-.468.351a1 1 0 0 0-.292 1.233 14 14 0 0 0 6.392 6.384",
      ),
    ]
    "brand" -> [
      Path("M2 9c2.5 0 2.5-2.5 5-2.5S9.5 9 12 9s2.5-2.5 5-2.5S19.5 9 22 9"),
      Path(
        "M2 16c2.5 0 2.5-2.5 5-2.5s2.5 2.5 5 2.5 2.5-2.5 5-2.5 2.5 2.5 5 2.5",
      ),
    ]
    _ -> []
  }
}

fn shape(s: Shape) -> Dom {
  let n = int.to_string
  case s {
    Path(d) -> dom.svg("path", [#("d", d)], [])
    Circle(cx, cy, r) ->
      dom.svg("circle", [#("cx", n(cx)), #("cy", n(cy)), #("r", n(r))], [])
    Rect(x, y, w, h, rx) ->
      dom.svg(
        "rect",
        [
          #("x", n(x)),
          #("y", n(y)),
          #("width", n(w)),
          #("height", n(h)),
          #("rx", n(rx)),
        ],
        [],
      )
  }
}

/// The 24 px icon of `name`, classed `ic ic-<name>`.
pub fn icon(name: String) -> Dom {
  dom.svg(
    "svg",
    [
      #("class", "ic ic-" <> name),
      #("viewBox", "0 0 24 24"),
      #("aria-hidden", "true"),
      #("focusable", "false"),
    ],
    list.map(shapes(name), shape),
  )
}
