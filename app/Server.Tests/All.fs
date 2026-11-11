module Marola.Server.Tests.All

open Expecto

let all =
    testList
        "server"
        [ HeaderTests.tests
          FileTests.tests
          LimitTests.tests
          ContactTests.tests
          StudyStoreTests.tests
          StudyStoreTests.devTests
          PdfTests.tests
          StudyApiTests.tests ]
