//// A small tree of elements and text, written once and drawn two ways: as
//// Lustre elements in the page, and as JSON that `maplibre_ffi.mjs` turns into
//// DOM nodes for a marker or a popup. No markup string is ever parsed, so a
//// beach name with `<` in it stays text.

import gleam/json.{type Json}
import gleam/list
import lustre/attribute
import lustre/element.{type Element}

pub type Dom {
  El(
    namespace: String,
    tag: String,
    attrs: List(#(String, String)),
    children: List(Dom),
  )
  Txt(String)
}

pub const svg_ns = "http://www.w3.org/2000/svg"

pub fn el(
  tag: String,
  attrs: List(#(String, String)),
  children: List(Dom),
) -> Dom {
  El("", tag, attrs, children)
}

pub fn svg(
  tag: String,
  attrs: List(#(String, String)),
  children: List(Dom),
) -> Dom {
  El(svg_ns, tag, attrs, children)
}

pub fn text(content: String) -> Dom {
  Txt(content)
}

pub fn to_json(dom: Dom) -> Json {
  case dom {
    Txt(content) -> json.string(content)
    El(namespace, tag, attrs, children) ->
      json.object([
        #("ns", json.string(namespace)),
        #("tag", json.string(tag)),
        #(
          "attrs",
          json.object(list.map(attrs, fn(a) { #(a.0, json.string(a.1)) })),
        ),
        #("children", json.array(children, to_json)),
      ])
  }
}

pub fn to_lustre(dom: Dom) -> Element(msg) {
  case dom {
    Txt(content) -> element.text(content)
    El(namespace, tag, attrs, children) -> {
      let attributes = list.map(attrs, fn(a) { attribute.attribute(a.0, a.1) })
      let kids = list.map(children, to_lustre)
      case namespace {
        "" -> element.element(tag, attributes, kids)
        _ -> element.namespaced(namespace, tag, attributes, kids)
      }
    }
  }
}
