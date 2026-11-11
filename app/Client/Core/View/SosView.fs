module Marola.Client.SosView

let private numbers = [ "193"; "190"; "192"; "185"; "199" ]

let private number (model: Model) (n: string) : Node<Msg> =
    Vdom.el
        "li"
        []
        [ Vdom.el
              "a"
              [ Vdom.attr "href" ("tel:" + n) ]
              [ Vdom.el "b" [] [ Vdom.text n ]
                Vdom.el "span" [] [ Vdom.text (Words.t model ("sos." + n)) ] ] ]

let private onEscape: Attr<Msg> =
    On("keydown", fun e -> if e.Key = "Escape" then Some SosClosed else None)

let view (model: Model) : Node<Msg> list =
    [ Vdom.el
          "button"
          [ Vdom.elId "sos"
            Vdom.attr "type" "button"
            Vdom.cls "sos"
            Vdom.attr "aria-controls" "sos-panel"
            Words.expanded model.SosOpen
            Vdom.onClick SosToggled ]
          [ Words.icon "phone"
            Vdom.el "span" [] [ Vdom.text (Words.t model "sos.open") ] ]
      Vdom.el
          "section"
          ([ Vdom.elId "sos-panel"
             Vdom.cls "sos-panel"
             Vdom.attr "aria-labelledby" "sos-title"
             onEscape ]
           @ Vdom.hidden (not model.SosOpen))
          [ Vdom.el
                "header"
                []
                [ Vdom.el "h2" [ Vdom.elId "sos-title" ] [ Vdom.text (Words.t model "sos.title") ]
                  Vdom.el
                      "button"
                      [ Vdom.elId "sos-close"
                        Vdom.attr "type" "button"
                        Vdom.attr "aria-label" (Words.t model "sos.close")
                        Vdom.onClick SosClosed ]
                      [ Vdom.text "×" ] ]
            Vdom.el "p" [] [ Vdom.text (Words.t model "sos.free") ]
            Vdom.el "ul" [] (List.map (number model) numbers)
            Vdom.el "p" [ Vdom.cls "sos-note" ] [ Vdom.text (Words.t model "sos.mobile") ] ] ]
