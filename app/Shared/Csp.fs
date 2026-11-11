namespace Marola

/// The Content-Security-Policy of the map page: one value, sent as an HTTP header by whatever
/// serves the page.
///
/// The page loads every script and style from `'self'`. Two third parties answer it: OpenFreeMap
/// for the base map and NASA GIBS for the satellite layers. `data:` and `blob:` are schemes, not
/// origins: MapLibre decodes its sprite sheet through an image built from a blob. It starts its
/// worker from a same-origin file, so `worker-src` needs no `blob:`; the vendored build uses a
/// blob worker only for a cross-origin or `null`-origin worker URL.
module Csp =

    let openfreemap = "tiles.openfreemap.org"

    let gibs = "gibs.earthdata.nasa.gov"

    let private origins () : string =
        [ openfreemap; gibs ]
        |> List.map (fun host -> "https://" + host)
        |> String.concat " "

    /// A header cannot carry a newline, so the directives join into one line.
    let policy () : string =
        [ "default-src 'self'"
          "script-src 'self'"
          "style-src 'self'"
          "img-src 'self' data: blob: " + origins ()
          "connect-src 'self' " + origins ()
          "font-src 'self'"
          "worker-src 'self'"
          "object-src 'none'"
          "base-uri 'self'"
          "frame-ancestors 'none'" ]
        |> String.concat "; "
