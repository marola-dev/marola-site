/// The virtual DOM: what `diff` asks of the DOM when one tree becomes another, and the JSON of a static tree.
module Marola.Tests.VdomTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola.Client

let private div attrs kids : Node<unit> = Vdom.el "div" attrs kids

let private li key text : Node<unit> =
    Vdom.keyed key (Vdom.el "li" [] [ Vdom.text text ])

let private ul kids : Node<unit> = Vdom.el "ul" [] kids

let private ops (a: Node<unit> list) (b: Node<unit> list) : string list = Vdom.diff a b |> List.map Vdom.show

let tests =
    testList
        "vdom"
        [ testCase "the same tree changes nothing"
          <| fun () ->
              let tree =
                  [ div [ Vdom.cls "a"; Attr("title", "t") ] [ Vdom.text "x"; Vdom.el "b" [] [] ] ]

              Expect.equal (ops tree tree) [] "no ops"

          testCase "a changed text is one SetText at its path"
          <| fun () ->
              let a =
                  [ div [] [ Vdom.el "p" [] [ Vdom.text "one" ]; Vdom.el "p" [] [ Vdom.text "two" ] ] ]

              let b =
                  [ div [] [ Vdom.el "p" [] [ Vdom.text "one" ]; Vdom.el "p" [] [ Vdom.text "2" ] ] ]

              Expect.equal (ops a b) [ "text 0/1/0 2" ] "text only"

          testCase "attributes: set what changed, remove what left, leave the rest"
          <| fun () ->
              let a = [ div [ Vdom.cls "a"; Attr("title", "t"); Attr("data-x", "1") ] [] ]
              let b = [ div [ Vdom.cls "b"; Attr("title", "t"); Attr("hidden", "") ] [] ]
              Expect.equal (ops a b) [ "unattr 0 data-x"; "attr 0 class=b"; "attr 0 hidden=" ] "attrs"

          testCase "properties and flags are set apart from attributes"
          <| fun () ->
              let a = [ Vdom.el "input" [ Prop("value", "1"); Flag("disabled", true) ] [] ]
              let b = [ Vdom.el "input" [ Prop("value", "2"); Flag("disabled", true) ] [] ]
              Expect.equal (ops a b) [ "prop 0 value=2" ] "prop"
              Expect.equal (ops b [ Vdom.el "input" [] [] ]) [ "prop 0 value="; "flag 0 disabled=false" ] "gone"

          testCase "another tag, or text for an element, replaces the node"
          <| fun () ->
              Expect.equal
                  (ops [ div [] [ Vdom.text "x" ] ] [ Vdom.el "section" [] [ Vdom.text "x" ] ])
                  [ "replace 0 <section>\"x\"" ]
                  "tag"

              Expect.equal (ops [ div [] [ Vdom.text "x" ] ] [ Vdom.text "x" ]) [ "replace 0 \"x\"" ] "kind"

          testCase "a namespace change replaces the node"
          <| fun () ->
              Expect.equal (ops [ Vdom.el "a" [] [] ] [ Vdom.svg "a" [] [] ]) [ "replace 0 <a>" ] "svg a is not html a"

          testCase "children without keys match by position: append and trim at the end"
          <| fun () ->
              let a = [ div [] [ Vdom.text "a" ] ]
              let more = [ div [] [ Vdom.text "a"; Vdom.text "b"; Vdom.text "c" ] ]
              Expect.equal (ops a more) [ "insert 0@1 \"b\""; "insert 0@2 \"c\"" ] "grow"
              Expect.equal (ops more a) [ "remove 0@2"; "remove 0@1" ] "shrink, last first"

          testCase "a handler is given again to a kept element, and only a closure is not compared"
          <| fun () ->
              let a = [ Vdom.el "button" [ Vdom.onClick () ] [] ]
              Expect.equal (ops a a) [ "on 0 click" ] "kept element, handlers refreshed"
              Expect.equal (ops a [ Vdom.el "button" [] [] ]) [ "on 0 " ] "handlers dropped"
              Expect.equal (ops [ Vdom.el "button" [] [] ] [ Vdom.el "button" [] [] ]) [] "none on both sides: no op"

          testCase "keyed: a removed item goes, the others stay where they are"
          <| fun () ->
              let a = [ ul [ li "a" "A"; li "b" "B"; li "c" "C" ] ]
              let b = [ ul [ li "a" "A"; li "c" "C" ] ]
              Expect.equal (ops a b) [ "remove 0@1" ] "only the removal"

          testCase "keyed: a new item is inserted, not written over its neighbour"
          <| fun () ->
              let a = [ ul [ li "a" "A"; li "c" "C" ] ]
              let b = [ ul [ li "a" "A"; li "b" "B"; li "c" "C" ] ]
              Expect.equal (ops a b) [ "insert 0@1 <li>\"B\"" ] "one insert"

          testCase "keyed: a reorder moves nodes and rewrites no text"
          <| fun () ->
              let a = [ ul [ li "a" "A"; li "b" "B"; li "c" "C" ] ]
              let b = [ ul [ li "c" "C"; li "a" "A"; li "b" "B" ] ]
              Expect.equal (ops a b) [ "move 0 2>0" ] "c moves to the front"

          testCase "keyed: a moved item that also changed is moved, then patched at its new place"
          <| fun () ->
              let a = [ ul [ li "a" "A"; li "b" "B" ] ]
              let b = [ ul [ li "b" "B2"; li "a" "A" ] ]
              Expect.equal (ops a b) [ "move 0 1>0"; "text 0/0/0 B2" ] "move first, then text at 0/0/0"

          testCase "duplicate keys fall back to positions"
          <| fun () ->
              let a = [ ul [ li "a" "A"; li "a" "B" ] ]
              let b = [ ul [ li "a" "B"; li "a" "A" ] ]
              Expect.equal (ops a b) [ "text 0/0/0 B"; "text 0/1/0 A" ] "positional"

          testCase "a static tree is JSON; text and markup in it stay text"
          <| fun () ->
              let tree =
                  Vdom.el "span" [ Vdom.cls "q"; Vdom.onClick () ] [ Vdom.text "<b>\"x\"</b>" ]

              Expect.equal
                  (Json.render (Vdom.toJson tree))
                  "{\"ns\":\"\",\"tag\":\"span\",\"attrs\":{\"class\":\"q\"},\"children\":[\"<b>\\\"x\\\"</b>\"]}"
                  "no handler, escaped" ]
