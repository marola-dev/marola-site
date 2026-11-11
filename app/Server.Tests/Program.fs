module Marola.Server.Tests.Program

open Expecto

[<EntryPoint>]
let main argv = runTestsWithCLIArgs [] argv All.all
