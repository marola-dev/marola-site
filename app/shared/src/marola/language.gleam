//// The two languages of the page and the choice between them (MIP-0054 5.5).

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Language {
  PtBr
  En
}

/// The language of the source text: a message missing elsewhere falls back to it.
pub const source = PtBr

pub const all = [PtBr, En]

pub fn tag(language: Language) -> String {
  case language {
    PtBr -> "pt-BR"
    En -> "en"
  }
}

/// A catalog key, exactly as the catalogs write it.
pub fn from_tag(value: String) -> Result(Language, Nil) {
  list.find(all, fn(language) { tag(language) == value })
}

/// A language tag against the supported ones: the exact tag first (ignoring
/// case), then the first with the same primary subtag ("pt" finds pt-BR).
pub fn matching(
  value: Option(String),
  supported: List(Language),
) -> Option(Language) {
  case value {
    None | Some("") -> None
    Some(raw) -> {
      let lower = string.lowercase(raw)
      let by = fn(wanted: String, primary: Bool) {
        list.find(supported, fn(language) {
          let candidate = string.lowercase(tag(language))
          case primary {
            True -> primary_subtag(candidate) == wanted
            False -> candidate == wanted
          }
        })
      }
      case by(lower, False) {
        Ok(language) -> Some(language)
        Error(Nil) ->
          case by(primary_subtag(lower), True) {
            Ok(language) -> Some(language)
            Error(Nil) -> None
          }
      }
    }
  }
}

fn primary_subtag(tag: String) -> String {
  case string.split(tag, "-") {
    [first, ..] -> first
    [] -> tag
  }
}

/// ?lang=, then the stored choice, then the browser's languages, then pt-BR.
pub fn resolve(
  param param: Option(String),
  stored stored: Option(String),
  languages languages: List(String),
  supported supported: List(Language),
) -> Language {
  let tags = [param, stored, ..list.map(languages, Some)]
  case
    list.find_map(tags, fn(t) { option.to_result(matching(t, supported), Nil) })
  {
    Ok(language) -> language
    Error(Nil) -> source
  }
}
