//// Text and links that reach the page. It replaces app.js `esc()`, and adds
//// the scheme check the old `lore.source` link never had.

import gleam/list
import gleam/string

/// Escapes the five characters that matter in HTML text and in a quoted
/// attribute. Lustre does this for its own text and attributes; this is for
/// the places that build markup by hand.
pub fn escape_html(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}

/// A link a page may put in an `href`: only `https:`, `http:` and `mailto:`.
/// It reads the URL the way a browser does, which drops tab and newline
/// anywhere and the control characters and spaces around it, so
/// "java\tscript:..." and " javascript:..." cannot slip through. The result is
/// that cleaned URL. It still needs attribute escaping where it is written.
pub fn safe_href(url: String) -> Result(String, Nil) {
  let cleaned =
    url
    |> string.replace("\t", "")
    |> string.replace("\n", "")
    |> string.replace("\r", "")
    |> trim_controls
  case string.split_once(cleaned, ":") {
    Ok(#(scheme, rest)) ->
      case
        rest != ""
        && valid_scheme(scheme)
        && list.contains(["https", "http", "mailto"], string.lowercase(scheme))
        && !has_control(cleaned)
      {
        True -> Ok(cleaned)
        False -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

fn codes(text: String) -> List(Int) {
  string.to_utf_codepoints(text) |> list.map(string.utf_codepoint_to_int)
}

fn trim_controls(text: String) -> String {
  let is_edge = fn(code: Int) { code <= 0x20 }
  let kept =
    codes(text)
    |> list.drop_while(is_edge)
    |> list.reverse
    |> list.drop_while(is_edge)
    |> list.reverse
  kept
  |> list.filter_map(string.utf_codepoint)
  |> string.from_utf_codepoints
}

fn has_control(text: String) -> Bool {
  list.any(codes(text), fn(code) {
    code < 0x20 || { code >= 0x7F && code <= 0x9F }
  })
}

/// RFC 3986: a letter, then letters, digits, "+", "-" or ".".
fn valid_scheme(scheme: String) -> Bool {
  case codes(scheme) {
    [first, ..rest] -> is_letter(first) && list.all(rest, is_scheme_char)
    [] -> False
  }
}

fn is_letter(code: Int) -> Bool {
  { code >= 0x41 && code <= 0x5A } || { code >= 0x61 && code <= 0x7A }
}

fn is_scheme_char(code: Int) -> Bool {
  is_letter(code)
  || { code >= 0x30 && code <= 0x39 }
  || code == 0x2B
  || code == 0x2D
  || code == 0x2E
}
