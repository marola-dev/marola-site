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
          SessionTests.tests
          LoginTests.tests
          WebTests.tests
          PdfTests.tests
          PdfTests.objStmTests
          BoardTests.tests
          StudyApiTests.tests
          OpenApiTests.tests ]
