/// The policy keeps the page's promise: no inline code, no wildcard, and only the origins the
/// page talks to.
module Marola.Tests.CspTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola

let private directives () : (string * string list) list =
    (Csp.policy ()).Split ';'
    |> Array.toList
    |> List.map (fun directive ->
        match directive.Trim().Split ' ' |> Array.toList with
        | name :: values -> name, values
        | [] -> "", [])

let private valuesOf (name: string) : string list =
    match directives () |> List.tryFind (fun (n, _) -> n = name) with
    | Some(_, values) -> values
    | None -> failwithf "no directive %s" name

let private tokens () : string list = directives () |> List.collect snd

let tests =
    testList
        "csp"
        [ testCase "the policy has no unsafe keyword and no wildcard"
          <| fun () ->
              let policy = Csp.policy ()

              for word in [ "unsafe-inline"; "unsafe-eval"; "wasm-unsafe-eval"; "strict-dynamic" ] do
                  Expect.isFalse (policy.Contains word) word

              for token in [ "*"; "https:"; "http:" ] do
                  Expect.isFalse (List.contains token (tokens ())) token

          testCase "the policy lists only the known origins"
          <| fun () ->
              let allowed =
                  [ "'self'"
                    "'none'"
                    "data:"
                    "blob:"
                    "https://tiles.openfreemap.org"
                    "https://gibs.earthdata.nasa.gov" ]

              Expect.equal (tokens () |> List.filter (fun t -> not (List.contains t allowed))) [] "allowed only"

              let hosts =
                  tokens ()
                  |> List.filter (fun t -> t.StartsWith "https://")
                  |> List.distinct
                  |> List.sortWith (fun a b -> System.String.CompareOrdinal(a, b))

              Expect.equal hosts [ "https://gibs.earthdata.nasa.gov"; "https://tiles.openfreemap.org" ] "hosts"

          testCase "third parties reach only images and fetches"
          <| fun () ->
              let third = [ "https://tiles.openfreemap.org"; "https://gibs.earthdata.nasa.gov" ]

              let withThird =
                  directives ()
                  |> List.filter (fun (_, values) -> values |> List.exists (fun v -> List.contains v third))
                  |> List.map fst

              Expect.equal withThird [ "img-src"; "connect-src" ] "directives"

          testCase "scripts, styles and workers come from self alone"
          <| fun () ->
              for name in [ "script-src"; "style-src"; "worker-src"; "default-src" ] do
                  Expect.equal (valuesOf name) [ "'self'" ] name

          testCase "the policy closes plugins, base and framing"
          <| fun () ->
              Expect.equal (valuesOf "object-src") [ "'none'" ] "object-src"
              Expect.equal (valuesOf "base-uri") [ "'self'" ] "base-uri"
              Expect.equal (valuesOf "frame-ancestors") [ "'none'" ] "frame-ancestors" ]
