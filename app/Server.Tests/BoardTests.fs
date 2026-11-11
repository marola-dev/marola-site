module Marola.Server.Tests.BoardTests

open System
open System.IO
open Expecto
open Microsoft.Data.Sqlite
open Marola.Server
open Marola.Server.Tests.PdfTests
open Marola.Server.Tests.StudyStoreTests

let private now = DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero)

/// A config with a migrated database and a studies folder; everything goes away after the test.
let private withBoard (body: Config -> unit) =
    withConfig 10_000_000L (fun config ->
        try
            Store.init config.Db
            StudyStore.migrate config.Db
            Directory.CreateDirectory config.Studies |> ignore
            body config
        finally
            SqliteConnection.ClearAllPools())

/// Runs a command; the exit code, what it wrote to stdout and what it wrote to stderr.
let private run (config: Config) (args: string list) =
    use out = new StringWriter()
    use err = new StringWriter()
    let code = Board.run config now args out err
    code, out.ToString(), err.ToString()

/// A stored study with a real file on disk, named by its hash.
let private addStudy (config: Config) (githubId: int64) (login: string) (title: string) (hash: char) : string =
    StudyStore.upsertAccount config.Db now (account githubId login)

    let sha = hashOf hash
    File.WriteAllBytes(PdfIntake.pathOf config sha, validPdf)

    (StudyStore.insertStudy config.Db now (account githubId login) sha { submission with Title = title }).Value.Id

let private noControls (text: string) =
    text |> Seq.forall (fun c -> c = '\n' || not (Char.IsControl c))

let tests =
    testList
        "board"
        [ test "clean replaces controls, escape sequences, line breaks and bidi marks, and keeps letters" {
              let hostile = "a\u001b[2J\u0007b\r\nc\u202Ed\u2028e\u0085f\u0000g Ação 😀"
              let cleaned = Board.clean hostile
              Expect.equal cleaned "a [2J b  c d e f g Ação 😀" "controls become spaces"
              Expect.isTrue (cleaned |> Seq.forall (fun c -> not (Char.IsControl c))) "none left"
          }

          test "studies list shows every status, filters, limits and prints one safe line for each" {
              withBoard (fun config ->
                  let a = addStudy config 1L "ana" "First study here" 'a'

                  let b =
                      addStudy config 2L "bruno" "Evil \u001b]0;pwned\u0007 title\r\n#99 forged" 'b'

                  Expect.isTrue (StudyStore.hide config.Db now b "wrong unit") "hide"

                  let code, out, _ = run config [ "studies"; "list" ]
                  Expect.equal code 0 "exit"
                  Expect.isTrue (noControls out) "no control character"
                  let lines = out.TrimEnd().Split '\n'
                  Expect.equal lines.Length 2 "one line each, a title cannot forge a line"
                  Expect.isTrue (out.Contains "hidden 2026-11-11T12:00:00Z: wrong unit") "the reason of the tombstone"

                  let _, hiddenOnly, _ = run config [ "studies"; "list"; "--status"; "hidden" ]
                  Expect.isTrue (hiddenOnly.Contains b && not (hiddenOnly.Contains a)) "filter"

                  let _, one, _ = run config [ "studies"; "list"; "--limit"; "1" ]
                  Expect.equal (one.TrimEnd().Split '\n').Length 1 "limit"

                  Expect.equal (let c, _, _ = run config [ "studies"; "list"; "--status"; "gone" ] in c) 2 "bad status"
                  Expect.equal (let c, _, _ = run config [ "studies"; "list"; "--limit"; "0" ] in c) 2 "bad limit"
                  Expect.equal (let c, _, _ = run config [ "studies"; "list"; "--limit" ] in c) 2 "missing value")
          }

          test "hide needs a reason of 5 to 300 characters, hides, keeps the file and says so twice only once" {
              withBoard (fun config ->
                  let id = addStudy config 1L "ana" "First study here" 'a'

                  for args in
                      [ [ "studies"; "hide"; id ]
                        [ "studies"; "hide"; id; "--reason"; "abcd" ]
                        [ "studies"; "hide"; id; "--reason"; String('x', 301) ]
                        [ "studies"; "hide"; id; "--reason"; "     \u0007 " ] ] do
                      let code, _, _ = run config args
                      Expect.equal code 2 (String.concat " " args)

                  Expect.equal (StudyStore.getStudy config.Db id).Value.Status Marola.Study.Public "still public"

                  let code, out, _ =
                      run config [ "studies"; "hide"; id; "--reason"; "wrong claim\u001b[31m about a beach" ]

                  Expect.equal code 0 "exit"
                  Expect.isTrue (out.Contains $"hidden {id}") "said"
                  let study = (StudyStore.getStudy config.Db id).Value
                  Expect.equal study.Status Marola.Study.Hidden "hidden"

                  Expect.equal
                      study.HiddenReason
                      (Some "wrong claim [31m about a beach")
                      "the stored reason has no control character"

                  Expect.isTrue (File.Exists(PdfIntake.pathOf config study.Sha256)) "the file stays"

                  let again, _, err = run config [ "studies"; "hide"; id; "--reason"; "second time" ]
                  Expect.equal again 1 "already hidden"
                  Expect.isTrue (err.Contains "hidden already") "message"

                  Expect.equal
                      (let c, _, _ =
                          run config [ "studies"; "hide"; "nosuchid"; "--reason"; "valid reason" ] in

                       c)
                      1
                      "no such study")
          }

          test "hide --purge deletes the file, keeps the row, the hash and the reason, and unhide is then refused" {
              withBoard (fun config ->
                  let id = addStudy config 1L "ana" "First study here" 'a'
                  let path = PdfIntake.pathOf config (hashOf 'a')

                  let code, out, _ =
                      run config [ "studies"; "hide"; id; "--reason"; "defamation"; "--purge" ]

                  Expect.equal code 0 "exit"
                  Expect.isTrue (out.Contains $"purged {hashOf 'a'} (file deleted)") "the line for the record"
                  Expect.isFalse (File.Exists path) "the file is gone"
                  let study = (StudyStore.getStudy config.Db id).Value
                  Expect.equal study.Sha256 (hashOf 'a') "hash kept"
                  Expect.equal study.HiddenReason (Some "defamation") "reason kept"
                  Expect.isSome (StudyStore.purgedUtc config.Db id) "marked"

                  let c, _, err = run config [ "studies"; "unhide"; id ]
                  Expect.equal c 1 "refused"
                  Expect.isTrue (err.Contains "purged") "says why"
                  Expect.equal (StudyStore.getStudy config.Db id).Value.Status Marola.Study.Hidden "still hidden")
          }

          test "a purge is refused while another public study uses the same file, and changes nothing" {
              withBoard (fun config ->
                  let one = addStudy config 1L "ana" "First study here" 'a'
                  let two = addStudy config 2L "bruno" "Second study here" 'a'

                  let code, _, err =
                      run config [ "studies"; "hide"; one; "--reason"; "defamation"; "--purge" ]

                  Expect.equal code 1 "refused"
                  Expect.isTrue (err.Contains two) "names the other study"
                  Expect.equal (StudyStore.getStudy config.Db one).Value.Status Marola.Study.Public "nothing changed"
                  Expect.isTrue (File.Exists(PdfIntake.pathOf config (hashOf 'a'))) "file kept"

                  // Hide the other first, then the purge goes through for both: they share one file.
                  Expect.equal
                      (let c, _, _ = run config [ "studies"; "hide"; two; "--reason"; "same file" ] in c)
                      0
                      "hide two"

                  Expect.equal
                      (let c, _, _ =
                          run config [ "studies"; "hide"; one; "--reason"; "defamation"; "--purge" ] in

                       c)
                      0
                      "purge"

                  Expect.isSome (StudyStore.purgedUtc config.Db two) "both are marked: one file")
          }

          test "unhide shows a hidden study again; a public one and a deleted account are refused" {
              withBoard (fun config ->
                  let id = addStudy config 1L "ana" "First study here" 'a'
                  Expect.equal (let c, _, _ = run config [ "studies"; "unhide"; id ] in c) 1 "public already"
                  run config [ "studies"; "hide"; id; "--reason"; "check pending" ] |> ignore
                  let c, out, _ = run config [ "studies"; "unhide"; id ]
                  Expect.equal c 0 "exit"
                  Expect.isTrue (out.Contains $"public {id}") "said"
                  let study = (StudyStore.getStudy config.Db id).Value
                  Expect.equal study.Status Marola.Study.Public "public"
                  Expect.isNone study.HiddenReason "reason cleared"

                  StudyStore.deleteAccount config.Db now 1L |> ignore
                  let c2, _, err = run config [ "studies"; "unhide"; id ]
                  Expect.equal c2 1 "refused"
                  Expect.isTrue (err.Contains "deleted the account") "says why")
          }

          test "reports lists them with safe text, --open hides closed ones, close needs a note and works once" {
              withBoard (fun config ->
                  let id = addStudy config 1L "ana" "First study here" 'a'

                  StudyStore.insertReport config.Db now id "harmful\u001b[2J\r\n#77  forged  study x open"
                  |> ignore

                  StudyStore.insertReport config.Db now id "second one" |> ignore

                  let code, out, _ = run config [ "reports" ]
                  Expect.equal code 0 "exit"
                  Expect.isTrue (noControls out) "no control character"

                  Expect.equal
                      (out.TrimEnd().Split '\n').Length
                      4
                      "two lines for each report: a text cannot forge a line"

                  Expect.isFalse (out.Contains "\n#77") "no forged report line"

                  Expect.equal (let c, _, _ = run config [ "reports"; "close"; "1" ] in c) 2 "a note is required"
                  Expect.equal (let c, _, _ = run config [ "reports"; "close"; "1"; "--note"; "x" ] in c) 2 "too short"

                  Expect.equal
                      (let c, _, _ = run config [ "reports"; "close"; "abc"; "--note"; "fine note" ] in c)
                      2
                      "bad id"

                  let c, closed, _ =
                      run config [ "reports"; "close"; "1"; "--note"; "hid the study\u001b[0m" ]

                  Expect.equal c 0 "closed"
                  Expect.isTrue (closed.Contains "closed #1") "said"

                  let _, open', _ = run config [ "reports"; "--open" ]
                  Expect.equal (open'.TrimEnd().Split '\n').Length 2 "one open report"
                  Expect.isFalse (open'.Contains "#1 ") "the closed one is not listed"

                  let _, all, _ = run config [ "reports" ]
                  Expect.isTrue (all.Contains "closed 2026-11-11T12:00:00Z: hid the study [0m") "the note"

                  Expect.equal
                      (let c, _, _ = run config [ "reports"; "close"; "1"; "--note"; "again fine" ] in c)
                      1
                      "closed already"

                  Expect.equal
                      (let c, _, _ = run config [ "reports"; "close"; "99"; "--note"; "no such" ] in c)
                      1
                      "no such report")
          }

          test "wrong usage is 2, and a missing database is 1 and is not created" {
              withConfig 1L (fun config ->
                  Expect.equal (let c, _, _ = run config [ "studies"; "list" ] in c) 1 "no database"
                  Expect.isFalse (File.Exists config.Db) "not created"
                  Expect.equal (let c, _, _ = run config [ "nonsense" ] in c) 2 "unknown command"

                  withBoard (fun config ->
                      Expect.equal (let c, _, _ = run config [ "studies" ] in c) 2 "no subcommand"
                      Expect.equal (let c, _, _ = run config [ "studies"; "hide" ] in c) 2 "no id"
                      Expect.equal (let c, _, _ = run config [ "reports"; "--bogus" ] in c) 2 "unknown option"))
          } ]
