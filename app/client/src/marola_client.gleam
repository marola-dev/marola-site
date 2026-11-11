//// The map page of marola.dev. `scripts/app_build.sh` writes the one-line
//// `boot.mjs` that calls `main`: the page has no inline script.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import lustre
import lustre/effect.{type Effect}
import marola_client/effects
import marola_client/model.{type Model}
import marola_client/msg.{type Msg}
import marola_client/params
import marola_client/update.{type Env, Env}
import marola_client/view

/// What the browser says before the page starts: the FFI's `readEnv` JSON.
fn env() -> Env {
  let decoder = {
    use path <- decode.field("path", decode.string)
    use search <- decode.field("search", decode.string)
    use languages <- decode.field("languages", decode.list(decode.string))
    use reduced_motion <- decode.field("reduced_motion", decode.bool)
    decode.success(#(path, search, languages, reduced_motion))
  }
  let #(path, search, languages, reduced_motion) =
    json.parse(effects.read_env(), decoder)
    |> result.unwrap(#("/", "", [], False))
  Env(
    path:,
    query: params.parse(search),
    languages:,
    stored_language: case effects.read_language() {
      "" -> None
      tag -> Some(tag)
    },
    reduced_motion:,
  )
}

fn init(env: Env) -> #(Model, Effect(Msg)) {
  let #(model, cmds) = update.init(env)
  #(model, effects.run(cmds))
}

fn step(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  let #(next, cmds) = update.update(model, message)
  #(next, effects.run(cmds))
}

pub fn main() -> Nil {
  let app = lustre.application(init, step, view.view)
  let assert Ok(_) = lustre.start(app, "#app", env())
  Nil
}
