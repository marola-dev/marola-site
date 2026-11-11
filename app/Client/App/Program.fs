/// The page's entry point: Elmish runs `Update` and hands each model to a view that diffs the
/// virtual tree and patches the DOM. Fable calls no `main` itself, so the last line starts the page.
module Marola.Client.App.Program

open Elmish
open Browser
open Marola.Client

let private init (env: Env) : Model * Cmd<Msg> =
    let model, commands = Update.init env
    model, Effects.toElmish commands

let private step (message: Msg) (model: Model) : Model * Cmd<Msg> =
    let next, commands = Update.update model message
    next, Effects.toElmish commands

let main () : unit =
    let container = document.getElementById "app"
    let shown = ref []

    let view (model: Model) (dispatch: Msg -> unit) : unit =
        let next = Page.view model
        Dom.patch container dispatch shown.Value next
        shown.Value <- next

    let env = Wire.env (Ffi.readEnv ()) (Ffi.readLanguage ())

    Program.mkProgram init step view |> Program.runWith env

main ()
