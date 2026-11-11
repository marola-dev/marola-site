/// The query string and the JSON writer that the map is told through.
module Marola.Tests.ParamsTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola.Client

let tests =
    testList
        "params and json"
        [ testCase "parse reads pairs, with or without the question mark"
          <| fun () ->
              Expect.equal (Params.parse "?area=rio&day=2026-09-07") [ "area", "rio"; "day", "2026-09-07" ] "with"
              Expect.equal (Params.parse "area=rio") [ "area", "rio" ] "without"
              Expect.equal (Params.parse "") [] "empty"
              Expect.equal (Params.parse "?") [] "only the mark"

          testCase "parse decodes percent escapes, plus and UTF-8, and keeps a stray percent"
          <| fun () ->
              Expect.equal (Params.get (Params.parse "?beach=Praia%20Brava") "beach") (Some "Praia Brava") "%20"
              Expect.equal (Params.get (Params.parse "?b=a+b") "b") (Some "a b") "plus"
              Expect.equal (Params.get (Params.parse "?b=%C3%A7") "b") (Some "ç") "utf-8"
              Expect.equal (Params.get (Params.parse "?b=100%") "b") (Some "100%") "stray"
              Expect.equal (Params.get (Params.parse "?b=%zz") "b") (Some "%zz") "not hex"

          testCase "a key with no value reads as empty, and an absent key as none"
          <| fun () ->
              Expect.equal (Params.parse "?flag") [ "flag", "" ] "bare key"
              Expect.equal (Params.get [] "x") None "absent"

          testCase "set replaces in place or adds at the end; delete removes every copy"
          <| fun () ->
              let q = [ "a", "1"; "b", "2" ]
              Expect.equal (Params.set q "a" "9") [ "a", "9"; "b", "2" ] "replace in place"
              Expect.equal (Params.set q "c" "3") [ "a", "1"; "b", "2"; "c", "3" ] "add at the end"
              Expect.equal (Params.delete [ "a", "1"; "b", "2"; "a", "3" ] "a") [ "b", "2" ] "delete"

          testCase "toString encodes what a URL cannot hold and round-trips through parse"
          <| fun () ->
              let q = [ "beach", "Praia da Joaquina"; "x", "a&b=c#d"; "n", "ção" ]
              let text = Params.toString q
              Expect.equal text "beach=Praia%20da%20Joaquina&x=a%26b%3Dc%23d&n=%C3%A7%C3%A3o" "text"
              Expect.equal (Params.parse text) q "round trip"

          testCase "json renders every kind and escapes what it must"
          <| fun () ->
              let json =
                  JObj
                      [ "s", JStr "a\"b\\c\nd\u0001"
                        "n", JNum 1.5
                        "i", JInt -3
                        "z", JNull
                        "b", JBool true
                        "l", JArr [ JInt 1; JBool false ]
                        "nan", JNum nan ]

              Expect.equal
                  (Json.render json)
                  "{\"s\":\"a\\\"b\\\\c\\nd\\u0001\",\"n\":1.5,\"i\":-3,\"z\":null,\"b\":true,\"l\":[1,false],\"nan\":null}"
                  "text" ]
