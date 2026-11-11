//// The policy keeps the page's promise: no inline code, no wildcard, and only
//// the origins the page talks to.

import gleam/list
import gleam/string
import marola/csp

fn directives() -> List(#(String, List(String))) {
  csp.policy()
  |> string.split(";")
  |> list.map(fn(directive) {
    case string.split(string.trim(directive), " ") {
      [name, ..values] -> #(name, values)
      [] -> #("", [])
    }
  })
}

fn values_of(name: String) -> List(String) {
  case list.key_find(directives(), name) {
    Ok(values) -> values
    Error(Nil) -> panic as { "no directive " <> name }
  }
}

pub fn policy_has_no_unsafe_keyword_and_no_wildcard_test() {
  let policy = csp.policy()
  assert !string.contains(policy, "unsafe-inline")
  assert !string.contains(policy, "unsafe-eval")
  assert !string.contains(policy, "wasm-unsafe-eval")
  assert !string.contains(policy, "strict-dynamic")
  let tokens = list.flat_map(directives(), fn(d) { d.1 })
  assert !list.contains(tokens, "*")
  assert !list.contains(tokens, "https:")
  assert !list.contains(tokens, "http:")
}

pub fn policy_lists_only_the_known_origins_test() {
  let allowed = [
    "'self'",
    "'none'",
    "data:",
    "blob:",
    "https://tiles.openfreemap.org",
    "https://gibs.earthdata.nasa.gov",
  ]
  let tokens = list.flat_map(directives(), fn(d) { d.1 })
  assert list.filter(tokens, fn(t) { !list.contains(allowed, t) }) == []
  let hosts =
    list.filter(tokens, fn(t) { string.starts_with(t, "https://") })
    |> list.unique
    |> list.sort(string.compare)
  assert hosts
    == ["https://gibs.earthdata.nasa.gov", "https://tiles.openfreemap.org"]
}

pub fn third_parties_reach_only_images_and_fetches_test() {
  let third = [
    "https://tiles.openfreemap.org",
    "https://gibs.earthdata.nasa.gov",
  ]
  let with_third =
    list.filter(directives(), fn(d) {
      list.any(d.1, fn(v) { list.contains(third, v) })
    })
    |> list.map(fn(d) { d.0 })
  assert with_third == ["img-src", "connect-src"]
}

pub fn scripts_styles_and_workers_come_from_self_alone_test() {
  assert values_of("script-src") == ["'self'"]
  assert values_of("style-src") == ["'self'"]
  assert values_of("worker-src") == ["'self'"]
  assert values_of("default-src") == ["'self'"]
}

pub fn policy_closes_plugins_base_and_framing_test() {
  assert values_of("object-src") == ["'none'"]
  assert values_of("base-uri") == ["'self'"]
  assert values_of("frame-ancestors") == ["'none'"]
}
