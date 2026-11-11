//// The site's navigation row, with the language toggle.

import lustre/attribute.{attribute, class, href}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import marola/language.{type Language}
import marola_client/dom
import marola_client/model.{type Model}
import marola_client/msg.{type Msg}
import marola_client/view/text.{t}

fn link(model: Model, url: String, key: String) -> Element(Msg) {
  html.a([href(url)], [html.text(t(model, key))])
}

fn lang_button(model: Model, language: Language, label: String, name: String) {
  html.button(
    [
      attribute.type_("button"),
      attribute("lang", language.tag(language)),
      attribute("aria-label", name),
      attribute("aria-pressed", case model.loc.language == language {
        True -> "true"
        False -> "false"
      }),
      event.on_click(msg.LanguagePicked(language)),
    ],
    [html.text(label)],
  )
}

fn svg(
  attrs: List(#(String, String)),
  children: List(dom.Dom),
) -> Element(Msg) {
  dom.svg(
    "svg",
    [#("aria-hidden", "true"), #("focusable", "false"), ..attrs],
    children,
  )
  |> dom.to_lustre
}

fn language_toggle(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.id("lang"),
      class("lang"),
      attribute("role", "group"),
      attribute("aria-label", t(model, "lang.label")),
    ],
    [
      svg([#("class", "lang-icon"), #("viewBox", "0 0 16 16")], [
        dom.svg("circle", [#("cx", "8"), #("cy", "8"), #("r", "6.5")], []),
        dom.svg(
          "ellipse",
          [#("cx", "8"), #("cy", "8"), #("rx", "2.8"), #("ry", "6.5")],
          [],
        ),
        dom.svg("path", [#("d", "M1.5 8h13")], []),
      ]),
      lang_button(model, language.PtBr, "PT-BR", "português (Brasil)"),
      lang_button(model, language.En, "EN", "English"),
    ],
  )
}

fn linkedin(model: Model) -> Element(Msg) {
  html.a(
    [
      class("li"),
      href("https://www.linkedin.com/company/marola-dev/"),
      attribute("target", "_blank"),
      attribute("rel", "noopener"),
      attribute("aria-label", t(model, "li.label")),
      attribute.title(t(model, "li.label")),
    ],
    [
      svg([#("class", "li-mark"), #("viewBox", "0 0 24 24")], [
        dom.svg(
          "path",
          [
            #(
              "d",
              "M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-4 0v7h-4v-7a6 6 0 0 1 6-6z",
            ),
          ],
          [],
        ),
        dom.svg(
          "rect",
          [#("x", "2"), #("y", "9"), #("width", "4"), #("height", "12")],
          [],
        ),
        dom.svg("circle", [#("cx", "4"), #("cy", "4"), #("r", "2")], []),
      ]),
      html.span([class("li-name")], [html.text(t(model, "li.name"))]),
    ],
  )
}

const github_mark =
  "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.06-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"

fn github(model: Model) -> Element(Msg) {
  html.a(
    [
      class("gh"),
      href("https://github.com/marola-dev/marola"),
      attribute("aria-label", t(model, "gh.label")),
      attribute.title(t(model, "gh.title")),
    ],
    [
      svg([#("class", "gh-mark"), #("viewBox", "0 0 16 16")], [
        dom.svg("path", [#("fill", "currentColor"), #("d", github_mark)], []),
      ]),
      html.span([class("gh-name")], [
        html.span([class("gh-owner")], [html.text("marola-dev/")]),
        html.text("marola"),
      ]),
      html.span([class("gh-star")], [
        svg([#("viewBox", "0 0 16 16")], [
          dom.svg(
            "path",
            [
              #(
                "d",
                "M8 1.6l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.4l-3.8 2 .7-4.3-3.1-3 4.3-.6z",
              ),
            ],
            [],
          ),
        ]),
        html.span([], [html.text(t(model, "gh.star"))]),
      ]),
    ],
  )
}

pub fn view(model: Model) -> Element(Msg) {
  html.nav([class("sitenav"), attribute("aria-label", t(model, "nav.label"))], [
    link(model, "https://docs.marola.dev/", "nav.docs"),
    html.span([attribute("aria-disabled", "true")], [
      html.span([], [html.text(t(model, "nav.alerts"))]),
      html.text(" "),
      html.i([], [html.text(t(model, "nav.soon"))]),
    ]),
    link(model, "news.html", "nav.news"),
    link(model, "about.html", "nav.about"),
    link(model, "contact.html", "nav.contact"),
    link(
      model,
      "https://github.com/marola-dev/marola-research/blob/main/README.md",
      "nav.research",
    ),
    link(
      model,
      "https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf",
      "nav.contribute",
    ),
    link(model, "members.html", "nav.members"),
    link(model, "support.html", "nav.donate"),
    language_toggle(model),
    linkedin(model),
    github(model),
  ])
}
