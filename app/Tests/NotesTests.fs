/// Note lines, day names and signed numbers, against the real catalogs and the text `Intl` prints.
module Marola.Tests.NotesTests

#if FABLE_COMPILER
open Fable.Mocha
#else
open Expecto
#endif
open Marola
open Marola.Tests.Support

let private shown (notes: string list) (codes: Note list) : Shown =
    { H = "10:00"
      Score = 50
      Notes = notes
      NoteCodes = codes
      Best = false }

let private code (c: NoteCode) (args: (string * NoteArg) list) : Note = { Code = c; Args = Map.ofList args }

let tests =
    testList
        "notes"
        [ testCase "a short date matches Intl in both languages"
          <| fun () ->
              Expect.equal (DateFmt.short "2026-01-07" Language.PtBr) "7 de jan." "jan"
              Expect.equal (DateFmt.short "2026-11-30" Language.PtBr) "30 de nov." "nov"
              Expect.equal (DateFmt.short "2026-05-07" Language.PtBr) "7 de mai." "mai"
              Expect.equal (DateFmt.short "2026-09-01" Language.En) "Sep 1" "sep"
              Expect.equal (DateFmt.short "2026-12-25" Language.En) "Dec 25" "dec"

          testCase "a short date keeps what is not a day"
          <| fun () ->
              Expect.equal (DateFmt.short "soon" Language.En) "soon" "word"
              Expect.equal (DateFmt.short "2026-13-01" Language.En) "2026-13-01" "month 13"
              Expect.equal (DateFmt.short "2026-00-01" Language.PtBr) "2026-00-01" "month 0"
              Expect.equal (DateFmt.short "" Language.PtBr) "" "empty"

          testCase "signed prints a sign unless the number is zero"
          <| fun () ->
              let pt = locale Language.PtBr
              Expect.equal (Fmt.signed pt 0.5 1) "+0,5" "plus"
              Expect.equal (Fmt.signed pt (-0.3) 1) "-0,3" "minus"
              Expect.equal (Fmt.signed pt 0.0 1) "0,0" "zero"
              Expect.equal (Fmt.signed pt (-0.04) 1) "0,0" "rounds to zero"
              Expect.equal (Fmt.signed pt 1.25 1) "+1,3" "half up"
              Expect.equal (Fmt.signed (locale Language.En) (-1.25) 1) "-1.3" "english"

          testCase "a code reads in the page language with rounded numbers"
          <| fun () ->
              let choppy = code NoteCode.Choppy [ "wave_m", NoteArg.Number 1.26 ]

              let line l =
                  Notes.ofShown (shown [ "choppy (1.26m waves)" ] [ choppy ]) l

              Expect.equal (line (locale Language.PtBr)) [ "mar picado (ondas de 1,3 m)" ] "pt"
              Expect.equal (line (locale Language.En)) [ "choppy (1.3m waves)" ] "en"

          testCase "a board without codes keeps its English lines"
          <| fun () -> Expect.equal (Notes.ofShown (shown [ "dark" ] []) (locale Language.PtBr)) [ "dark" ] "schema 1"

          testCase "a code with no key keeps the board English"
          <| fun () ->
              let newCode = code (NoteCode.Unknown "kelp_bloom") []
              let pt = locale Language.PtBr

              Expect.equal
                  (Notes.ofShown (shown [ "kelp on the beach" ] [ newCode ]) pt)
                  [ "kelp on the beach" ]
                  "english"
              // No English line at the same position: the code itself.
              Expect.equal (Notes.ofShown (shown [] [ newCode ]) pt) [ "kelp_bloom" ] "code"

          testCase "lines pair with codes by position"
          <| fun () ->
              let codes = [ code NoteCode.Dark []; code NoteCode.NoWindData [] ]

              Expect.equal
                  (Notes.ofShown (shown [ "a"; "b" ] codes) (locale Language.En))
                  [ "dark"; "no wind data" ]
                  "positions"

          testCase "unfit water prints the day and a missing count"
          <| fun () ->
              let unfit =
                  code
                      NoteCode.WaterUnfit
                      [ "source", NoteArg.Text "IMA/SC"
                        "sampled_on", NoteArg.Text "2026-11-03"
                        "point", NoteArg.Text "P1"
                        "location", NoteArg.Text "Canasvieiras"
                        "enterococci_per_100ml", NoteArg.Other ]

              Expect.equal
                  (Notes.text unfit None (locale Language.En))
                  "water unfit for bathing: IMA/SC Nov 3, P1 (Canasvieiras), count n/a"
                  "line"

          testCase "unfit water prints a count when there is one"
          <| fun () ->
              let unfit =
                  code
                      NoteCode.WaterUnfit
                      [ "source", NoteArg.Text "IMA/SC"
                        "sampled_on", NoteArg.Text "2026-11-03"
                        "point", NoteArg.Text "P1"
                        "location", NoteArg.Text "Canasvieiras"
                        "enterococci_per_100ml", NoteArg.Number 1200.0 ]

              Expect.stringContains (Notes.text unfit None (locale Language.PtBr)) "1.200 enterococos" "count"

          testCase "mixed water lists the places to avoid"
          <| fun () ->
              let mixed =
                  code
                      NoteCode.WaterMixed
                      [ "proper", NoteArg.Number 2.0
                        "total", NoteArg.Number 3.0
                        "avoid", NoteArg.Places [ "P1"; "P2" ] ]

              Expect.equal (Notes.text mixed (Some "x") (locale Language.En)) "2/3 points PRÓPRIA; avoid P1; P2" "line"

          testCase "a message that does not parse gives its key"
          <| fun () ->
              let catalog = catalogOf [ "broken", "{a"; "fine", "ok" ]

              let loc =
                  { Catalog = catalog
                    Language = Language.En }

              Expect.equal (I18n.t loc "broken" []) "broken" "broken"
              Expect.equal (I18n.t loc "fine" []) "ok" "fine"
              Expect.equal (I18n.t loc "fine" [ "x", Num 1.0 ]) "ok" "unused arg"

          testCase "minusDays crosses months, years and leap days"
          <| fun () ->
              Expect.equal (DateFmt.minusDays "2026-11-11" 1) "2026-11-10" "day"
              Expect.equal (DateFmt.minusDays "2026-11-01" 2) "2026-10-30" "month"
              Expect.equal (DateFmt.minusDays "2026-01-01" 1) "2025-12-31" "year"
              Expect.equal (DateFmt.minusDays "2024-03-01" 1) "2024-02-29" "leap 2024"
              Expect.equal (DateFmt.minusDays "2025-03-01" 1) "2025-02-28" "2025"
              Expect.equal (DateFmt.minusDays "2000-03-01" 1) "2000-02-29" "leap 2000"
              Expect.equal (DateFmt.minusDays "1900-03-01" 1) "1900-02-28" "1900"
              Expect.equal (DateFmt.minusDays "2026-11-11" 0) "2026-11-11" "zero"
              Expect.equal (DateFmt.minusDays "2026-03-01" 365) "2025-03-01" "a year"

          testCase "minusDays keeps what is not a day"
          <| fun () ->
              Expect.equal (DateFmt.minusDays "soon" 1) "soon" "word"
              Expect.equal (DateFmt.minusDays "2026-13-01" 1) "2026-13-01" "month 13"
              Expect.equal (DateFmt.minusDays "" 2) "" "empty" ]
