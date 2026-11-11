module Marola.Tests.All

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif

/// Every test, in one list: .NET (Expecto) and Node (Fable.Mocha) run this same value.
let all =
    testList
        "marola"
        [ TypesTests.tests
          BoardTests.tests
          CspTests.tests
          HtmlTests.tests
          StudyTests.tests
          NotesTests.tests
          TrailsTests.tests
          ParityBeachTests.tests
          ParityFlowTests.tests
          ParityTextTests.tests
          VdomTests.tests
          ParamsTests.tests
          UpdateTests.tests
          MapTests.tests
          ViewBarTests.tests
          ViewPageTests.tests ]
