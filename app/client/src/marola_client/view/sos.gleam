//// The emergency numbers. The numbers and the idea are Carlos Toledo's
//// swell-floripa (#76); `tel:` links dial on a phone.

import gleam/dynamic/decode
import gleam/list
import lustre/attribute.{attribute, class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import marola_client/model.{type Model}
import marola_client/msg.{type Msg}
import marola_client/view/text.{expanded, hidden, icon, t}

const numbers = ["193", "190", "192", "185", "199"]

fn number(model: Model, n: String) -> Element(Msg) {
  html.li([], [
    html.a([attribute.href("tel:" <> n)], [
      html.b([], [html.text(n)]),
      html.span([], [html.text(t(model, "sos." <> n))]),
    ]),
  ])
}

fn on_escape() -> attribute.Attribute(Msg) {
  event.on("keydown", {
    use key <- decode.field("key", decode.string)
    case key {
      "Escape" -> decode.success(msg.SosClosed)
      _ -> decode.failure(msg.SosClosed, "key")
    }
  })
}

pub fn view(model: Model) -> List(Element(Msg)) {
  [
    html.button(
      [
        attribute.id("sos"),
        attribute.type_("button"),
        class("sos"),
        attribute("aria-controls", "sos-panel"),
        expanded(model.sos_open),
        event.on_click(msg.SosToggled),
      ],
      [icon("phone"), html.span([], [html.text(t(model, "sos.open"))])],
    ),
    html.section(
      [
        attribute.id("sos-panel"),
        class("sos-panel"),
        attribute("aria-labelledby", "sos-title"),
        on_escape(),
        ..hidden(!model.sos_open)
      ],
      [
        html.header([], [
          html.h2([attribute.id("sos-title")], [
            html.text(t(model, "sos.title")),
          ]),
          html.button(
            [
              attribute.id("sos-close"),
              attribute.type_("button"),
              attribute("aria-label", t(model, "sos.close")),
              event.on_click(msg.SosClosed),
            ],
            [html.text("×")],
          ),
        ]),
        html.p([], [html.text(t(model, "sos.free"))]),
        html.ul([], list.map(numbers, number(model, _))),
        html.p([class("sos-note")], [html.text(t(model, "sos.mobile"))]),
      ],
    ),
  ]
}
