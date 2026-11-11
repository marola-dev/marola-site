module Marola.Server.Tests.StudyStoreTests

open System
open System.IO
open Expecto
open Microsoft.Data.Sqlite
open Marola
open Marola.Server

let private now = DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero)

/// A migrated database in a temp folder; the folder goes away after the test.
let withDb (body: string -> unit) =
    let dir =
        Path.Combine(Path.GetTempPath(), "marola-store-" + Guid.NewGuid().ToString "N")

    let db = Path.Combine(dir, "marola.db")

    try
        Store.init db
        StudyStore.migrate db
        body db
    finally
        SqliteConnection.ClearAllPools()
        Directory.Delete(dir, true)

let account id login : StudyStore.Account =
    { GithubId = id
      Login = login
      CreatedGithubUtc = "2020-01-01T00:00:00Z" }

let submission: Study.Submission =
    { Title = "Water at Leblon"
      Authors =
        [ { Name = "Ana Silva"
            Orcid = Some "0000-0002-1825-0097" }
          { Name = "Bruno Costa"; Orcid = None } ]
      Abstract = String.replicate 10 "Enterococcus counts at six points. "
      Area = Study.Rio
      Topic = Study.WaterQuality
      Sources = [ "https://example.org/a"; "https://example.org/b" ]
      Repository = Some "https://github.com/example/r"
      Licence = Study.CcBy40
      AiModels = ""
      AiContribution = Study.NoAi
      AiProcess = "" }

let hashOf (c: char) = String.replicate 64 (string c)

let tests =
    testList
        "study store"
        [ test "the migration creates the four tables, sets user_version and runs twice without harm" {
              withDb (fun db ->
                  Expect.equal (StudyStore.version db) (int64 StudyStore.schemaVersion) "version"
                  let tables = StudyStore.tableNames db

                  for t in [ "accounts"; "api_keys"; "studies"; "reports"; "messages" ] do
                      Expect.contains tables t t

                  StudyStore.upsertAccount db now (account 1L "ana")
                  StudyStore.migrate db
                  Expect.equal (StudyStore.version db) (int64 StudyStore.schemaVersion) "same version"
                  Expect.isSome (StudyStore.getAccount db 1L) "data kept")
          }

          test "a database of the contact form (version 0, with messages) migrates and keeps the messages" {
              withDb (fun db ->
                  Store.insert db now "ana@example.org" "A message with some words." |> ignore
                  StudyStore.migrate db
                  Expect.equal (List.length (Store.list db)) 1 "message kept")
          }

          test "an account updates its login and keeps its GitHub creation date" {
              withDb (fun db ->
                  StudyStore.upsertAccount db now (account 7L "old")

                  StudyStore.upsertAccount
                      db
                      now
                      { account 7L "new" with
                          CreatedGithubUtc = "2024-01-01T00:00:00Z" }

                  let a = (StudyStore.getAccount db 7L).Value
                  Expect.equal a.Login "new" "login"
                  Expect.equal a.CreatedGithubUtc "2020-01-01T00:00:00Z" "the date from the first login stands")
          }

          test "a key is msk_ and 52 base32 characters, verifies, and only its hash is stored" {
              withDb (fun db ->
                  StudyStore.upsertAccount db now (account 1L "ana")

                  let key =
                      StudyStore.issueKey db now 1L |> Result.defaultWith (fun _ -> failwith "no key")

                  Expect.isTrue (key.StartsWith "msk_") "prefix"
                  Expect.equal key.Length 56 "length"
                  Expect.isTrue (StudyStore.keyShape key) "shape"
                  Expect.equal (StudyStore.verifyKey db key |> Option.map (fun a -> a.Login)) (Some "ana") "verifies"

                  Expect.isNone
                      (StudyStore.verifyKey db (key.Substring(0, 55) + (if key.EndsWith "a" then "b" else "a")))
                      "a wrong key"

                  Expect.isNone (StudyStore.verifyKey db "msk_") "short"
                  Expect.isNone (StudyStore.verifyKey db null) "null"
                  // The key itself is nowhere in the file.
                  SqliteConnection.ClearAllPools()
                  Expect.isFalse (File.ReadAllText(db, Text.Encoding.Latin1).Contains key) "not stored in the clear"

                  Expect.isTrue
                      (File.ReadAllText(db, Text.Encoding.Latin1).Contains(StudyStore.hashKey key))
                      "its hash is")
          }

          test "at most three active keys per account; a revoked key frees a place and stops working" {
              withDb (fun db ->
                  StudyStore.upsertAccount db now (account 1L "ana")
                  StudyStore.upsertAccount db now (account 2L "bia")
                  let issue () = StudyStore.issueKey db now 1L

                  let keys =
                      [ for _ in 1..3 -> (issue ()) |> Result.defaultWith (fun _ -> failwith "no key") ]

                  Expect.equal (issue ()) (Error StudyStore.TooManyKeys) "the fourth"
                  Expect.isOk (StudyStore.issueKey db now 2L) "another account is not affected"
                  let first = (StudyStore.listKeys db 1L).Head
                  Expect.isFalse (StudyStore.revokeKey db now 2L first.Id) "another account cannot revoke it"
                  Expect.isTrue (StudyStore.revokeKey db now 1L first.Id) "revoke"
                  Expect.isFalse (StudyStore.revokeKey db now 1L first.Id) "twice"
                  Expect.isNone (StudyStore.verifyKey db keys.Head) "revoked"
                  Expect.isSome (StudyStore.verifyKey db keys.[1]) "the others work"
                  Expect.isOk (issue ()) "a place is free again")
          }

          test "a study round-trips, and the same file from the same account is refused once" {
              withDb (fun db ->
                  let ana = account 1L "ana"
                  StudyStore.upsertAccount db now ana
                  StudyStore.upsertAccount db now (account 2L "bia")
                  let r = (StudyStore.insertStudy db now ana (hashOf 'a') submission).Value
                  Expect.isTrue (Study.validId r.Id) "id shape"
                  Expect.equal (StudyStore.getStudy db r.Id) (Some r) "read back"
                  Expect.isNone (StudyStore.insertStudy db now ana (hashOf 'a') submission) "duplicate"
                  Expect.equal (StudyStore.findByHash db 1L (hashOf 'a')) (Some r.Id) "the old id"

                  Expect.isSome
                      (StudyStore.insertStudy db now (account 2L "bia") (hashOf 'a') submission)
                      "another account"

                  Expect.isSome (StudyStore.insertStudy db now ana (hashOf 'b') submission) "another file")
          }

          test "ids are not sequential" {
              withDb (fun db ->
                  let ana = account 1L "ana"
                  StudyStore.upsertAccount db now ana

                  let ids =
                      [ for i in 0..19 ->
                            (StudyStore.insertStudy db now ana (hashOf (char (int 'a' + i))) submission).Value.Id ]

                  Expect.equal (List.length (List.distinct ids)) 20 "distinct"
                  Expect.notEqual ids (List.sort ids) "not in order")
          }

          test "the list is newest first, filters by area and topic and pages with before" {
              withDb (fun db ->
                  let ana = account 1L "ana"
                  StudyStore.upsertAccount db now ana

                  let add i area topic =
                      (StudyStore.insertStudy
                          db
                          (now.AddMinutes(float i))
                          ana
                          (hashOf (char (int 'a' + i)))
                          { submission with
                              Area = area
                              Topic = topic })
                          .Value.Id

                  let a = add 0 Study.Rio Study.WaterQuality
                  let b = add 1 Study.Floripa Study.Waves
                  let c = add 2 Study.Rio Study.Waves

                  let ids rs =
                      rs |> List.map (fun (r: Study.Record) -> r.Id)

                  Expect.equal (ids (StudyStore.listStudies db None None None 50)) [ c; b; a ] "newest first"
                  Expect.equal (ids (StudyStore.listStudies db (Some Study.Rio) None None 50)) [ c; a ] "area"

                  Expect.equal
                      (ids (StudyStore.listStudies db (Some Study.Rio) (Some Study.Waves) None 50))
                      [ c ]
                      "both"

                  Expect.equal (ids (StudyStore.listStudies db None None (Some c) 1)) [ b ] "before and limit"

                  Expect.isEmpty
                      (StudyStore.listStudies db None None (Some "zzzzzzzzzz") 50)
                      "an unknown cursor ends the list")
          }

          test "hide keeps the row and marks it; counts since a time" {
              withDb (fun db ->
                  let ana = account 1L "ana"
                  StudyStore.upsertAccount db now ana
                  let r = (StudyStore.insertStudy db now ana (hashOf 'a') submission).Value
                  Expect.equal (StudyStore.countSince db 1L (now.AddMinutes -1.)) 1L "in the window"
                  Expect.equal (StudyStore.countSince db 1L (now.AddMinutes 1.)) 0L "outside"
                  Expect.isTrue (StudyStore.hide db now r.Id "wrong unit") "hidden"
                  Expect.isFalse (StudyStore.hide db now r.Id "again") "once"
                  let h = (StudyStore.getStudy db r.Id).Value
                  Expect.equal (h.Status, h.HiddenReason) (Study.Hidden, Some "wrong unit") "tombstone")
          }

          test "a study of an unknown account is refused by the foreign key" {
              withDb (fun db ->
                  Expect.throws
                      (fun () ->
                          StudyStore.insertStudy db now (account 99L "ghost") (hashOf 'a') submission
                          |> ignore)
                      "foreign key")
          } ]

let private devAccount (db: string) (dev: string) (args: string list) =
    let config: Config =
        { Port = 0
          Static = ""
          Data = ""
          Db = db
          Studies = ""
          StudiesQuota = 0L
          Dev = false
          GithubClientId = None
          GithubSecretFile = None
          GithubBase = ""
          GithubApiBase = "" }

    let out, err = new StringWriter(), new StringWriter()
    let code = DevAccount.run config now dev args out err
    code, out.ToString().Trim(), err.ToString()

let devTests =
    testList
        "dev-account"
        [ test "it refuses unless MAROLA_DEV=1 and creates nothing" {
              withDb (fun db ->
                  let code, out, _ = devAccount db "" [ "--login"; "ana"; "--age-days"; "30" ]
                  Expect.equal (code, out) (1, "") "refused"
                  Expect.isEmpty (StudyStore.listKeys db 1L) "no key"
                  let code, _, _ = devAccount db "0" [ "--login"; "ana"; "--age-days"; "30" ]
                  Expect.equal code 1 "only 1 counts")
          }

          test "it makes an account of the given age and a working key, and a third key is the last" {
              withDb (fun db ->
                  let code, key, _ = devAccount db "1" [ "--login"; "ana"; "--age-days"; "30" ]
                  Expect.equal code 0 "ok"
                  let account = (StudyStore.verifyKey db key).Value
                  Expect.equal account.Login "ana" "login"
                  Expect.equal account.CreatedGithubUtc "2026-10-12T12:00:00Z" "30 days before now"
                  devAccount db "1" [ "--login"; "ana"; "--age-days"; "30" ] |> ignore
                  devAccount db "1" [ "--login"; "ana"; "--age-days"; "30" ] |> ignore
                  let code, _, err = devAccount db "1" [ "--login"; "ana"; "--age-days"; "30" ]
                  Expect.equal code 1 "fourth refused"
                  Expect.stringContains err "3 active keys" "message")
          }

          test "bad arguments print the usage" {
              withDb (fun db ->
                  Expect.equal (devAccount db "1" [ "--login"; "ana" ] |> (fun (c, _, _) -> c)) 2 "missing age"

                  Expect.equal
                      (devAccount db "1" [ "--login"; "ana"; "--age-days"; "x" ]
                       |> (fun (c, _, _) -> c))
                      2
                      "not a number")
          } ]
