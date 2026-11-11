//// The footer: the status line, which reads as the board's provenance once a
//// board is on show, and the folds for the sea lore and for the privacy note.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute.{attribute, class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import marola/board.{type Board}
import marola/html as safe
import marola/i18n
import marola/lore.{type Lore}
import marola_client/config
import marola_client/model.{type Model} as mdl
import marola_client/msg.{type Msg}
import marola_client/view/text.{expanded, hidden, icon, t, ta, with_slot}

fn yes(on: Bool) -> String {
  case on {
    True -> "yes"
    False -> "no"
  }
}

fn source(name: String) -> Element(Msg) {
  let label = case config.source_link(name) {
    Some(href) ->
      html.a(
        [
          attribute.href(href),
          attribute.target("_blank"),
          attribute.rel("noopener"),
        ],
        [html.text(name)],
      )
    None -> html.text(name)
  }
  html.span([class("src")], [label])
}

fn sources(board: Board) -> List(Element(Msg)) {
  [
    Some(board.sources.beaches),
    Some(board.sources.forecast),
    board.sources.water,
  ]
  |> list.filter_map(option.to_result(_, Nil))
  |> list.map(source)
  |> list.intersperse(html.text(" · "))
}

fn when(board: Board) -> String {
  string.replace(board.generated_at, "T", " ") |> string.slice(0, 16)
}

fn provenance(model: Model, board: Board) -> List(Element(Msg)) {
  let area = case model.area {
    Some(a) -> a.name
    None -> board.area
  }
  with_slot(
    model,
    "footer.generated",
    [
      i18n.arg("when", when(board)),
      i18n.arg("area", area),
      i18n.arg("day", board.day),
      i18n.number_arg("n", int.to_float(list.length(board.beaches))),
    ],
    "sources",
    sources(board),
  )
}

/// What the status line says: a load in progress or failed, else the board.
pub fn status_line(model: Model) -> List(Element(Msg)) {
  case model.status {
    mdl.Loading(name) -> [
      html.text(ta(model, "status.loading_named", [i18n.arg("name", name)])),
    ]
    mdl.Failed(error, missing) -> [
      html.text(
        ta(model, "fail.load", [
          i18n.arg("error", error),
          i18n.arg("hint", yes(missing)),
        ]),
      ),
    ]
    mdl.NoAreas -> [html.text(t(model, "fail.no_areas"))]
    mdl.TooNew(schema) -> [
      html.text(
        ta(model, "fail.schema", [
          i18n.arg("got", int.to_string(schema)),
          i18n.arg(
            "want",
            list.map(board.schemas, int.to_string) |> string.join(", "),
          ),
        ]),
      ),
    ]
    mdl.Idle ->
      case model.board {
        Some(board) -> provenance(model, board)
        None -> [html.text(t(model, "status.loading"))]
      }
  }
}

fn fold_button(
  id: String,
  label: String,
  open: Bool,
  message: Msg,
) -> Element(Msg) {
  html.button(
    [
      attribute.type_("button"),
      class("fold"),
      attribute("data-fold", id),
      attribute("aria-controls", "footer-" <> id),
      expanded(open),
      event.on_click(message),
    ],
    [
      html.span([class("pm"), attribute("aria-hidden", "true")], []),
      html.text(label),
    ],
  )
}

fn lore_panel(model: Model, found: Lore) -> Element(Msg) {
  let link = case safe.safe_href(found.source) {
    Ok(href) -> [
      html.text(" "),
      html.a(
        [
          attribute.href(href),
          attribute.target("_blank"),
          attribute.rel("noopener"),
        ],
        [html.text("[" <> t(model, "lore.source") <> "]")],
      ),
    ]
    Error(Nil) -> []
  }
  let name = case found.kind {
    lore.Creature -> "fish"
    _ -> "book"
  }
  html.p(
    [
      attribute.id("footer-lore"),
      class("fold-panel lore"),
      ..hidden(!model.lore_open)
    ],
    [icon(name), html.text(" " <> found.text), ..link],
  )
}

fn blurb_panel(model: Model) -> Element(Msg) {
  html.p(
    [
      attribute.id("footer-blurb"),
      class("fold-panel"),
      ..hidden(!model.blurb_open)
    ],
    [
      html.text(t(model, "footer.blurb") <> " "),
      html.a(
        [
          attribute.href(config.repo),
          attribute.target("_blank"),
          attribute.rel("noopener"),
        ],
        [html.text(t(model, "footer.github"))],
      ),
      html.text("."),
    ],
  )
}

fn lore_of(model: Model) -> Option(Lore) {
  option.then(model.board, fn(board) { board.lore })
}

pub fn view(model: Model) -> Element(Msg) {
  let lore = lore_of(model)
  let folds =
    list.flatten([
      case lore {
        Some(found) -> [
          fold_button(
            "lore",
            t(model, lore.label_key(found.kind)),
            model.lore_open,
            msg.FoldToggled(msg.LoreFold),
          ),
        ]
        None -> []
      },
      [
        fold_button(
          "blurb",
          t(model, "footer.about"),
          model.blurb_open,
          msg.FoldToggled(msg.BlurbFold),
        ),
        // A placeholder for a feature not built yet: focusable and named, but it opens nothing.
        html.button(
          [
            attribute.type_("button"),
            class("fold soon"),
            attribute("aria-disabled", "true"),
            attribute("aria-describedby", "footer-artists-soon"),
            attribute.title(t(model, "footer.artists_soon")),
          ],
          [
            html.span([class("pm"), attribute("aria-hidden", "true")], []),
            html.text(t(model, "footer.artists")),
          ],
        ),
        html.span([attribute.id("footer-artists-soon"), class("vh")], [
          html.text(t(model, "footer.artists_soon")),
        ]),
      ],
    ])
  html.footer([attribute.id("footer"), class("footer")], [
    html.div([class("footbar")], [
      html.p([attribute.id("status")], status_line(model)),
      html.div([class("folds")], folds),
    ]),
    ..list.flatten([
      case lore {
        Some(found) -> [lore_panel(model, found)]
        None -> []
      },
      [blurb_panel(model)],
    ])
  ])
}
