module Marola.Pages.Tests.HtmlTests

open Expecto
open Marola.Client

let private html (node: Node<unit>) : string = Vdom.toHtml node

let tests =
    testList
        "Vdom.toHtml"
        [ test "text keeps no markup" {
              Expect.equal
                  (html (Vdom.el "p" [] [ Vdom.text "<script>alert(\"x\")</script> & co" ]))
                  "<p>&lt;script&gt;alert(\"x\")&lt;/script&gt; &amp; co</p>"
                  "text escaped"
          }
          test "an attribute value cannot end its quote" {
              Expect.equal
                  (html (Vdom.el "a" [ Vdom.attr "href" "/a?b=1&c=\"><script>" ] []))
                  "<a href=\"/a?b=1&amp;c=&quot;&gt;&lt;script&gt;\"></a>"
                  "value escaped"
          }
          test "a void element has no closing tag, an empty one has" {
              Expect.equal
                  (html (Vdom.el "div" [] [ Vdom.el "img" [ Vdom.attr "alt" "" ] []; Vdom.el "span" [] [] ]))
                  "<div><img alt=\"\"><span></span></div>"
                  "void and empty"
          }
          test "flags print as bare names, handlers and false flags vanish" {
              Expect.equal
                  (html (Vdom.el "button" [ Flag("disabled", true); Flag("hidden", false); Vdom.onClick () ] []))
                  "<button disabled></button>"
                  "flags"
          }
          test "svg children keep their closing tags" {
              Expect.equal
                  (html (
                      Vdom.svg "svg" [ Vdom.attr "viewBox" "0 0 1 1" ] [ Vdom.svg "path" [ Vdom.attr "d" "M0 0" ] [] ]
                  ))
                  "<svg viewBox=\"0 0 1 1\"><path d=\"M0 0\"></path></svg>"
                  "svg"
          } ]
