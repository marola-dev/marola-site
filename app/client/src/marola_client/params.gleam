//// The page's query string (`?area=&day=&beach=&layer=&lang=&beaches=&trails=`).
//// It is state the visitor can share: each change replaces the URL in place.

import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/uri

pub type Query =
  List(#(String, String))

/// `location.search` with or without its leading `?`.
pub fn parse(search: String) -> Query {
  let bare = case search {
    "?" <> rest -> rest
    other -> other
  }
  uri.parse_query(bare) |> result.unwrap([])
}

pub fn get(query: Query, key: String) -> Option(String) {
  list.key_find(query, key) |> option.from_result
}

/// Replaces the key where it stands, or adds it at the end.
pub fn set(query: Query, key: String, value: String) -> Query {
  case list.key_find(query, key) {
    Ok(_) ->
      list.map(query, fn(pair) {
        case pair.0 == key {
          True -> #(key, value)
          False -> pair
        }
      })
    Error(Nil) -> list.append(query, [#(key, value)])
  }
}

pub fn delete(query: Query, key: String) -> Query {
  list.filter(query, fn(pair) { pair.0 != key })
}

pub fn to_string(query: Query) -> String {
  uri.query_to_string(query)
}
