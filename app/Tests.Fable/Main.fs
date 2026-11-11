module Marola.Tests.Fable.Main

open Fable.Mocha

[<EntryPoint>]
let main argv = Mocha.runTests Marola.Tests.All.all
