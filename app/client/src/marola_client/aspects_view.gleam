//// The aspect cells of a beach: the tooltip over its dot and the first rows
//// of its card. Every icon is followed by its word: the icon is decoration,
//// the word is the reading.

import gleam/list
import gleam/option.{None, Some}
import marola/aspects.{type Aspects, type Cell}
import marola_client/dom.{type Dom}
import marola_client/icons

/// The head line, then the grid of readings; no grid when the beach is dark.
pub fn children(aspects: Aspects) -> List(Dom) {
  let head = dom.el("div", [#("class", "head")], [dom.text(aspects.head)])
  case aspects.cells {
    [] -> [head]
    cells -> [head, dom.el("div", [#("class", "grid")], list.map(cells, cell))]
  }
}

fn reading(icon: String, text: List(Dom)) -> Dom {
  dom.el("span", [], [icons.icon(icon), dom.text(" "), ..text])
}

fn cell(cell: Cell) -> Dom {
  case cell {
    aspects.Wind(text, None) -> reading("wind", [dom.text(text)])
    aspects.Wind(text, Some(direction)) ->
      reading("wind", [
        dom.text(text <> " "),
        dom.el("abbr", [#("class", "dir")], [dom.text(direction)]),
      ])
    aspects.WaterTemp(text) -> reading("thermometer", [dom.text(text)])
    aspects.Waves(text) -> reading("waves", [dom.text(text)])
    aspects.Jellyfish(text) -> reading("jellyfish", [dom.text(text)])
    aspects.Whales(text) -> reading("fish", [dom.text(text)])
    aspects.Quality(text, unfit, dot_class) ->
      dom.el(
        "span",
        [
          #("class", case unfit {
            True -> "wide unfit"
            False -> "wide water"
          }),
        ],
        [
          dom.el("i", [#("class", dot_class)], []),
          dom.text(" " <> text),
        ],
      )
    aspects.FacilityCounts(parts) ->
      dom.el(
        "span",
        [#("class", "wide facilities")],
        list.index_map(parts, fn(part, i) {
          let item = [icons.icon(part.key), dom.text(" " <> part.text)]
          case i {
            0 -> item
            _ -> [dom.text(" · "), ..item]
          }
        })
          |> list.flatten,
      )
  }
}
