module Marola.Pages.Tests.All

open Expecto

let all = testList "pages" [ HtmlTests.tests; MarkdownTests.tests; PageTests.tests ]
