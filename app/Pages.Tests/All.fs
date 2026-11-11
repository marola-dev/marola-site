module Marola.Pages.Tests.All

open Expecto

let all =
    testList
        "pages"
        [ HtmlTests.tests
          MarkdownTests.tests
          NewsTests.tests
          MembersTests.tests
          MetaTests.tests
          EqualityTests.tests
          PageTests.tests ]
