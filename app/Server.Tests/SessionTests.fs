module Marola.Server.Tests.SessionTests

open System
open System.IO
open Expecto
open Marola.Server
open Marola.Server.Tests.StudyStoreTests

let private now = DateTimeOffset(2026, 11, 11, 12, 0, 0, TimeSpan.Zero)

let private withAccount (body: string -> unit) =
    withDb (fun db ->
        StudyStore.upsertAccount db now (account 7L "ana")
        body db)

let tests =
    testList
        "sessions"
        [ test "a session is the account's for 12 hours, absolute, and then it is gone" {
              withAccount (fun db ->
                  let token = StudyStore.createSession db now 7L

                  match StudyStore.getSession db (now.AddHours 11.9) token with
                  | Some(a, _) -> Expect.equal a.Login "ana" "login"
                  | None -> failtest "live session not found"

                  Expect.isNone (StudyStore.getSession db (now.AddHours 12.) token) "expired at 12 h"
                  Expect.isNone (StudyStore.getSession db (now.AddDays 2.) token) "and later")
          }
          test "using a session does not extend it" {
              withAccount (fun db ->
                  let token = StudyStore.createSession db now 7L
                  Expect.isSome (StudyStore.getSession db (now.AddHours 11.) token) "used"
                  Expect.isNone (StudyStore.getSession db (now.AddHours 12.5) token) "still ends at 12 h")
          }
          test "only the hash is stored, and a tampered or short value finds nothing" {
              withAccount (fun db ->
                  let token = StudyStore.createSession db now 7L
                  Expect.equal token.Length 43 "32 bytes, url-safe"

                  use connection = new Microsoft.Data.Sqlite.SqliteConnection("Data Source=" + db)
                  connection.Open()
                  use command = connection.CreateCommand()
                  command.CommandText <- "select token_hash from sessions"
                  let stored = command.ExecuteScalar() :?> string
                  Expect.notEqual stored token "the cookie value is not stored"
                  Expect.equal stored.Length 64 "a SHA-256 in hex"

                  let flipped = (if token[0] = 'A' then "B" else "A") + token.Substring 1

                  for bad in [ flipped; token.Substring 1; token + "A"; ""; null; stored ] do
                      Expect.isNone (StudyStore.getSession db now bad) "no session")
          }
          test "logout deletes the row; another session of the account stays" {
              withAccount (fun db ->
                  let a = StudyStore.createSession db now 7L
                  let b = StudyStore.createSession db now 7L
                  Expect.isTrue (StudyStore.deleteSession db a) "deleted"
                  Expect.isFalse (StudyStore.deleteSession db a) "twice"
                  Expect.isNone (StudyStore.getSession db now a) "gone"
                  Expect.isSome (StudyStore.getSession db now b) "the other stays")
          }
          test "safeEquals: equal, different at the end, different length, null" {
              Expect.isTrue (Session.safeEquals "abc" "abc") "equal"
              Expect.isFalse (Session.safeEquals "abc" "abd") "last char"
              Expect.isFalse (Session.safeEquals "abc" "abcd") "length"
              Expect.isFalse (Session.safeEquals null "abc") "null"
              Expect.isFalse (Session.safeEquals "" null) "null right"
          }
          test "the CSRF token is bound to the session and to the key" {
              let dir =
                  Path.Combine(Path.GetTempPath(), "marola-key-" + Guid.NewGuid().ToString "N")

              try
                  let db = Path.Combine(dir, "m.db")
                  let key = Session.loadKey db
                  let file = Path.Combine(dir, "csrf.key")
                  Expect.equal (File.GetUnixFileMode file) (UnixFileMode.UserRead ||| UnixFileMode.UserWrite) "0600"
                  Expect.equal (Session.loadKey db) key "a restart keeps the key"

                  let token = Session.csrfToken key "session-a"
                  Expect.isTrue (Session.csrfValid key "session-a" token) "valid"
                  Expect.isFalse (Session.csrfValid key "session-b" token) "another session"
                  Expect.isFalse (Session.csrfValid key "session-a" "") "empty"
                  Expect.isFalse (Session.csrfValid key "session-a" (token.Substring 1 + "0")) "tampered"
                  Expect.isFalse (Session.csrfValid (Array.rev key) "session-a" token) "another key"
              finally
                  Directory.Delete(dir, true)
          } ]
