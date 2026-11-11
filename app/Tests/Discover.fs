module Marola.Tests.Discover

open Expecto

// The Test SDK adapter finds tests by this attribute; Fable has no such attribute, so only this project has the file.
[<Tests>]
let all = All.all
