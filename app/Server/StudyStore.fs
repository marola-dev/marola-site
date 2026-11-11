namespace Marola.Server

open System
open System.Security.Cryptography
open System.Text
open Microsoft.Data.Sqlite
open Marola.Study

/// Accounts, API keys, studies and reports in the SQLite file of the contact form. The schema moves by
/// `PRAGMA user_version`. No email address is stored anywhere here.
module StudyStore =

    type Account =
        { GithubId: int64
          Login: string
          CreatedGithubUtc: string }

    type KeyError = | TooManyKeys

    type KeyInfo =
        { Id: int64
          CreatedUtc: string
          RevokedUtc: string option }

    let maxActiveKeys = 3

    let utc (t: DateTimeOffset) : string =
        t.UtcDateTime.ToString "yyyy-MM-ddTHH:mm:ssZ"

    // ---- schema -------------------------------------------------------------------------------------

    /// Version 1 adds the four tables. A later change appends a step; it never edits this one.
    let private steps =
        [ 1,
          [ "create table accounts (
                 github_id integer primary key,
                 github_login text not null,
                 created_github_utc text not null,
                 created_utc text not null)"
            "create table api_keys (
                 id integer primary key autoincrement,
                 github_id integer not null references accounts(github_id),
                 key_hash text not null unique,
                 created_utc text not null,
                 revoked_utc text)"
            "create table studies (
                 id text primary key,
                 received_utc text not null,
                 sha256 text not null,
                 title text not null,
                 authors text not null,
                 abstract text not null,
                 area text not null,
                 topic text not null,
                 sources text not null,
                 repository text,
                 licence text not null,
                 ai_models text not null,
                 ai_contribution text not null,
                 ai_process text not null,
                 author_login text not null,
                 author_github_id integer not null references accounts(github_id),
                 status text not null default 'public',
                 hidden_reason text,
                 hidden_utc text,
                 unique (author_github_id, sha256))"
            "create index studies_received on studies (received_utc desc, id desc)"
            "create table reports (
                 id integer primary key autoincrement,
                 study_id text not null references studies(id),
                 created_utc text not null,
                 reason text not null,
                 reporter_github_id integer)" ]
          2,
          [ // Only the SHA-256 of the cookie value is stored: a copy of the database cannot log anyone in.
            "create table sessions (
                 token_hash text primary key,
                 github_id integer not null references accounts(github_id),
                 created_utc text not null,
                 expires_utc text not null)" ]
          3,
          [ // Account deletion detaches a study from its author. The old table had a foreign key to `accounts`,
            // which a detached study cannot satisfy, so the table is rebuilt without it (SQLite cannot drop a
            // constraint). `purged_utc` marks a file that the board deleted. A report can be closed with a note.
            "create table studies_new (
                 id text primary key,
                 received_utc text not null,
                 sha256 text not null,
                 title text not null,
                 authors text not null,
                 abstract text not null,
                 area text not null,
                 topic text not null,
                 sources text not null,
                 repository text,
                 licence text not null,
                 ai_models text not null,
                 ai_contribution text not null,
                 ai_process text not null,
                 author_login text not null,
                 author_github_id integer not null,
                 status text not null default 'public',
                 hidden_reason text,
                 hidden_utc text,
                 purged_utc text,
                 unique (author_github_id, sha256))"
            "insert into studies_new (id, received_utc, sha256, title, authors, abstract, area, topic, sources,
                 repository, licence, ai_models, ai_contribution, ai_process, author_login, author_github_id,
                 status, hidden_reason, hidden_utc)
             select id, received_utc, sha256, title, authors, abstract, area, topic, sources,
                 repository, licence, ai_models, ai_contribution, ai_process, author_login, author_github_id,
                 status, hidden_reason, hidden_utc from studies"
            "drop table studies"
            "alter table studies_new rename to studies"
            "create index studies_received on studies (received_utc desc, id desc)"
            // What the dropped foreign key did for a new study. A detached study has a negative author id, no account.
            "create trigger studies_author_exists before insert on studies
             when new.author_github_id > 0
               and not exists (select 1 from accounts where github_id = new.author_github_id)
             begin select raise(abort, 'FOREIGN KEY constraint failed: the author has no account'); end"
            "alter table reports add column closed_utc text"
            "alter table reports add column close_note text" ] ]

    let schemaVersion = steps |> List.map fst |> List.max

    let private open' (path: string) =
        let connection = Store.connect SqliteOpenMode.ReadWrite path

        use pragma =
            Store.run connection "pragma foreign_keys = on; pragma busy_timeout = 5000" []

        pragma.ExecuteNonQuery() |> ignore
        connection

    let private scalar (connection: SqliteConnection) sql parameters =
        use command = Store.run connection sql parameters
        command.ExecuteScalar()

    let version (path: string) : int64 =
        use connection = open' path
        scalar connection "pragma user_version" [] :?> int64

    /// Applies the steps above the file's `user_version`, each in a transaction. Safe to call at every start.
    /// Foreign keys are off while the steps run: step 3 drops and renames a table that `reports` points at.
    let migrate (path: string) : unit =
        use connection = open' path
        let current = scalar connection "pragma user_version" [] :?> int64

        use off = Store.run connection "pragma foreign_keys = off" []
        off.ExecuteNonQuery() |> ignore

        for (v, statements) in steps do
            if int64 v > current then
                use tx = connection.BeginTransaction()

                for sql in statements do
                    use command = Store.run connection sql []
                    command.Transaction <- tx
                    command.ExecuteNonQuery() |> ignore

                // `pragma` takes no bound parameter; `v` is an int constant of this file.
                use bump = Store.run connection ("pragma user_version = " + string v) []
                bump.Transaction <- tx
                bump.ExecuteNonQuery() |> ignore
                tx.Commit()

    // ---- accounts and keys --------------------------------------------------------------------------

    /// C3b's GitHub login calls this. A returning user updates the login, which GitHub lets people change.
    let upsertAccount (path: string) (now: DateTimeOffset) (account: Account) : unit =
        use connection = open' path

        use command =
            Store.run
                connection
                "insert into accounts (github_id, github_login, created_github_utc, created_utc)
                 values ($id, $login, $created, $now)
                 on conflict (github_id) do update set github_login = excluded.github_login"
                [ "$id", box account.GithubId
                  "$login", box account.Login
                  "$created", box account.CreatedGithubUtc
                  "$now", box (utc now) ]

        command.ExecuteNonQuery() |> ignore

    let getAccount (path: string) (githubId: int64) : Account option =
        use connection = open' path

        use command =
            Store.run
                connection
                "select github_id, github_login, created_github_utc from accounts where github_id = $id"
                [ "$id", box githubId ]

        use reader = command.ExecuteReader()

        if reader.Read() then
            Some
                { GithubId = reader.GetInt64 0
                  Login = reader.GetString 1
                  CreatedGithubUtc = reader.GetString 2 }
        else
            None

    let private base32 (bytes: byte[]) : string =
        // RFC 4648 alphabet, lower case, no padding. 32 bytes give 52 characters.
        let alphabet = idAlphabet
        let sb = StringBuilder()
        let mutable buffer = 0
        let mutable bits = 0

        for b in bytes do
            buffer <- (buffer <<< 8) ||| int b
            bits <- bits + 8

            while bits >= 5 do
                sb.Append alphabet[(buffer >>> (bits - 5)) &&& 31] |> ignore
                bits <- bits - 5

            buffer <- buffer &&& ((1 <<< bits) - 1)

        if bits > 0 then
            sb.Append alphabet[(buffer <<< (5 - bits)) &&& 31] |> ignore

        sb.ToString()

    let keyPrefix = "msk_"

    /// `msk_` and 52 base32 characters: the only text worth hashing and looking up.
    let keyShape (key: string) : bool =
        not (isNull key)
        && key.Length = keyPrefix.Length + 52
        && key.StartsWith(keyPrefix, StringComparison.Ordinal)
        && key.Substring(keyPrefix.Length)
           |> Seq.forall (fun c -> idAlphabet.IndexOf c >= 0)

    let hashKey (key: string) : string =
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes key)).ToLowerInvariant()

    /// A new key, shown once: only its SHA-256 is stored. At most three active keys per account.
    let issueKey (path: string) (now: DateTimeOffset) (githubId: int64) : Result<string, KeyError> =
        use connection = open' path
        use tx = connection.BeginTransaction()

        let active =
            use count =
                Store.run
                    connection
                    "select count(*) from api_keys where github_id = $id and revoked_utc is null"
                    [ "$id", box githubId ]

            count.Transaction <- tx
            count.ExecuteScalar() :?> int64

        if active >= int64 maxActiveKeys then
            Error TooManyKeys
        else
            let key = keyPrefix + base32 (RandomNumberGenerator.GetBytes 32)

            use insert =
                Store.run
                    connection
                    "insert into api_keys (github_id, key_hash, created_utc) values ($id, $hash, $now)"
                    [ "$id", box githubId; "$hash", box (hashKey key); "$now", box (utc now) ]

            insert.Transaction <- tx
            insert.ExecuteNonQuery() |> ignore
            tx.Commit()
            Ok key

    /// The account an active key belongs to. The lookup is by hash; the comparison of the stored hash
    /// with the computed one is constant time as well.
    let verifyKey (path: string) (key: string) : Account option =
        if not (keyShape key) then
            None
        else
            use connection = open' path
            let hash = hashKey key

            use command =
                Store.run
                    connection
                    "select k.key_hash, a.github_id, a.github_login, a.created_github_utc
                     from api_keys k join accounts a on a.github_id = k.github_id
                     where k.key_hash = $hash and k.revoked_utc is null"
                    [ "$hash", box hash ]

            use reader = command.ExecuteReader()

            if
                reader.Read()
                && CryptographicOperations.FixedTimeEquals(
                    ReadOnlySpan(Encoding.ASCII.GetBytes(reader.GetString 0)),
                    ReadOnlySpan(Encoding.ASCII.GetBytes hash)
                )
            then
                Some
                    { GithubId = reader.GetInt64 1
                      Login = reader.GetString 2
                      CreatedGithubUtc = reader.GetString 3 }
            else
                None

    let listKeys (path: string) (githubId: int64) : KeyInfo list =
        use connection = open' path

        use command =
            Store.run
                connection
                "select id, created_utc, revoked_utc from api_keys where github_id = $id order by id"
                [ "$id", box githubId ]

        use reader = command.ExecuteReader()

        [ while reader.Read() do
              { Id = reader.GetInt64 0
                CreatedUtc = reader.GetString 1
                RevokedUtc = if reader.IsDBNull 2 then None else Some(reader.GetString 2) } ]

    /// True when an active key of that account was revoked. A key of another account is never touched.
    let revokeKey (path: string) (now: DateTimeOffset) (githubId: int64) (keyId: int64) : bool =
        use connection = open' path

        use command =
            Store.run
                connection
                "update api_keys set revoked_utc = $now where id = $key and github_id = $id and revoked_utc is null"
                [ "$now", box (utc now); "$key", box keyId; "$id", box githubId ]

        command.ExecuteNonQuery() > 0

    // ---- sessions -----------------------------------------------------------------------------------

    /// A session lasts 12 hours from login, absolute: using it does not extend it.
    let sessionLifetime = TimeSpan.FromHours 12.

    let private tokenHash (token: string) : string =
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes token)).ToLowerInvariant()

    /// A random 32-byte value, URL-safe, 43 characters. The hash of it is the session's id everywhere else.
    let sessionTokenShape (token: string) : bool =
        not (isNull token)
        && token.Length = 43
        && token |> Seq.forall (fun c -> Char.IsAsciiLetterOrDigit c || c = '-' || c = '_')

    /// Returns the cookie value; the row holds its hash. Expired rows of any account go at the same time.
    let createSession (path: string) (now: DateTimeOffset) (githubId: int64) : string =
        use connection = open' path

        use purge =
            Store.run connection "delete from sessions where expires_utc <= $now" [ "$now", box (utc now) ]

        purge.ExecuteNonQuery() |> ignore

        let token =
            Convert.ToBase64String(RandomNumberGenerator.GetBytes 32).TrimEnd('=').Replace('+', '-').Replace('/', '_')

        use insert =
            Store.run
                connection
                "insert into sessions (token_hash, github_id, created_utc, expires_utc) values ($hash, $id, $now, $end)"
                [ "$hash", box (tokenHash token)
                  "$id", box githubId
                  "$now", box (utc now)
                  "$end", box (utc (now + sessionLifetime)) ]

        insert.ExecuteNonQuery() |> ignore
        token

    /// The account of a live session and the hash that names it. The lookup is by hash and the stored hash is
    /// compared in constant time too.
    let getSession (path: string) (now: DateTimeOffset) (token: string) : (Account * string) option =
        if not (sessionTokenShape token) then
            None
        else
            use connection = open' path
            let hash = tokenHash token

            use command =
                Store.run
                    connection
                    "select s.token_hash, a.github_id, a.github_login, a.created_github_utc
                     from sessions s join accounts a on a.github_id = s.github_id
                     where s.token_hash = $hash and s.expires_utc > $now"
                    [ "$hash", box hash; "$now", box (utc now) ]

            use reader = command.ExecuteReader()

            if
                reader.Read()
                && CryptographicOperations.FixedTimeEquals(
                    ReadOnlySpan(Encoding.ASCII.GetBytes(reader.GetString 0)),
                    ReadOnlySpan(Encoding.ASCII.GetBytes hash)
                )
            then
                Some(
                    { GithubId = reader.GetInt64 1
                      Login = reader.GetString 2
                      CreatedGithubUtc = reader.GetString 3 },
                    hash
                )
            else
                None

    /// Logout. True when a row was deleted.
    let deleteSession (path: string) (token: string) : bool =
        if not (sessionTokenShape token) then
            false
        else
            use connection = open' path

            use command =
                Store.run connection "delete from sessions where token_hash = $hash" [ "$hash", box (tokenHash token) ]

            command.ExecuteNonQuery() > 0

    // ---- studies ------------------------------------------------------------------------------------

    let private authorsText (authors: Author list) =
        authors
        |> List.map (fun a -> a.Name + "|" + defaultArg a.Orcid "")
        |> String.concat "\n"

    let private parseAuthors (text: string) : Author list =
        text.Split '\n'
        |> Array.map (fun l ->
            let i = l.LastIndexOf '|'

            { Name = l.Substring(0, i)
              Orcid =
                match l.Substring(i + 1) with
                | "" -> None
                | o -> Some o })
        |> Array.toList

    let private newId () : string =
        RandomNumberGenerator.GetBytes 10
        |> Array.map (fun b -> idAlphabet[int b &&& 31])
        |> String

    /// The study is public at once; `received_utc` is the server's clock. Returns the record, or `None`
    /// when this account already sent this file (the unique index), which the caller reports as a 409.
    let insertStudy
        (path: string)
        (now: DateTimeOffset)
        (account: Account)
        (sha256: string)
        (s: Submission)
        : Record option =
        use connection = open' path
        let id = newId ()

        use command =
            Store.run
                connection
                "insert into studies (id, received_utc, sha256, title, authors, abstract, area, topic, sources,
                     repository, licence, ai_models, ai_contribution, ai_process, author_login, author_github_id)
                 values ($id, $now, $sha, $title, $authors, $abstract, $area, $topic, $sources,
                     $repo, $licence, $models, $level, $process, $login, $gid)
                 on conflict (author_github_id, sha256) do nothing"
                [ "$id", box id
                  "$now", box (utc now)
                  "$sha", box sha256
                  "$title", box s.Title
                  "$authors", box (authorsText s.Authors)
                  "$abstract", box s.Abstract
                  "$area", box (areaName s.Area)
                  "$topic", box (topicName s.Topic)
                  "$sources", box (String.concat "\n" s.Sources)
                  "$repo",
                  (match s.Repository with
                   | Some r -> box r
                   | None -> box DBNull.Value)
                  "$licence", box (licenceName s.Licence)
                  "$models", box s.AiModels
                  "$level", box (levelName s.AiContribution)
                  "$process", box s.AiProcess
                  "$login", box account.Login
                  "$gid", box account.GithubId ]

        if command.ExecuteNonQuery() = 0 then
            None
        else
            Some
                { Id = id
                  ReceivedUtc = utc now
                  Sha256 = sha256
                  Submission = s
                  AuthorLogin = account.Login
                  AuthorGithubId = account.GithubId
                  Status = Public
                  HiddenReason = None
                  HiddenUtc = None }

    let private columns =
        "id, received_utc, sha256, title, authors, abstract, area, topic, sources, repository, licence,
         ai_models, ai_contribution, ai_process, author_login, author_github_id, status, hidden_reason, hidden_utc"

    let private readRecord (r: SqliteDataReader) : Record =
        let opt i =
            if r.IsDBNull i then None else Some(r.GetString i)

        let must name (o: 'a option) =
            match o with
            | Some v -> v
            | None -> failwith ("bad stored " + name)

        let sources = r.GetString 8

        { Id = r.GetString 0
          ReceivedUtc = r.GetString 1
          Sha256 = r.GetString 2
          Submission =
            { Title = r.GetString 3
              Authors = parseAuthors (r.GetString 4)
              Abstract = r.GetString 5
              Area = parseArea (r.GetString 6) |> must "area"
              Topic = parseTopic (r.GetString 7) |> must "topic"
              Sources =
                if sources = "" then
                    []
                else
                    sources.Split '\n' |> Array.toList
              Repository = opt 9
              Licence = parseLicence (r.GetString 10) |> must "licence"
              AiModels = r.GetString 11
              AiContribution = parseLevel (r.GetString 12) |> must "level"
              AiProcess = r.GetString 13 }
          AuthorLogin = r.GetString 14
          AuthorGithubId = r.GetInt64 15
          Status = parseStatus (r.GetString 16) |> must "status"
          HiddenReason = opt 17
          HiddenUtc = opt 18 }

    let getStudy (path: string) (id: string) : Record option =
        use connection = open' path

        use command =
            Store.run connection ("select " + columns + " from studies where id = $id") [ "$id", box id ]

        use reader = command.ExecuteReader()
        if reader.Read() then Some(readRecord reader) else None

    /// Public studies only, newest first. `before` is the id of the last study of the previous page. Ids are random, so the
    /// order is by `received_utc`, then `id`, and `before` is resolved to that pair.
    let listStudies
        (path: string)
        (area: Area option)
        (topic: Topic option)
        (before: string option)
        (limit: int)
        : Record list =
        use connection = open' path

        let sql =
            "select "
            + columns
            + " from studies
             where status = 'public' and ($area is null or area = $area) and ($topic is null or topic = $topic)
               and ($before is null or (received_utc, id) < (select received_utc, id from studies where id = $before))
             order by received_utc desc, id desc limit $limit"

        let text f o =
            match o with
            | Some v -> box (f v)
            | None -> box DBNull.Value

        use command =
            Store.run
                connection
                sql
                [ "$area", text areaName area
                  "$topic", text topicName topic
                  "$before", text id before
                  "$limit", box limit ]

        use reader = command.ExecuteReader()

        [ while reader.Read() do
              readRecord reader ]

    let countSince (path: string) (githubId: int64) (since: DateTimeOffset) : int64 =
        use connection = open' path

        scalar
            connection
            "select count(*) from studies where author_github_id = $id and received_utc >= $since"
            [ "$id", box githubId; "$since", box (utc since) ]
        :?> int64

    let findByHash (path: string) (githubId: int64) (sha256: string) : string option =
        use connection = open' path

        match
            scalar
                connection
                "select id from studies where author_github_id = $id and sha256 = $sha"
                [ "$id", box githubId; "$sha", box sha256 ]
        with
        | :? string as id -> Some id
        | _ -> None

    /// The board's tombstone: the file stays on disk, the API stops serving it. True when a public study was hidden.
    let hide (path: string) (now: DateTimeOffset) (id: string) (reason: string) : bool =
        use connection = open' path

        use command =
            Store.run
                connection
                "update studies set status = 'hidden', hidden_reason = $reason, hidden_utc = $now
                 where id = $id and status = 'public'"
                [ "$reason", box reason; "$now", box (utc now); "$id", box id ]

        command.ExecuteNonQuery() > 0

    let tableNames (path: string) : string list =
        use connection = open' path

        use command =
            Store.run
                connection
                "select name from sqlite_master where type = 'table' and name not like 'sqlite_%' order by name"
                []

        use reader = command.ExecuteReader()

        [ while reader.Read() do
              reader.GetString 0 ]

    // ---- the web side -------------------------------------------------------------------------------

    /// Every study of one account, hidden ones too, newest first: the account page lists them.
    let listByAuthor (path: string) (githubId: int64) : Record list =
        use connection = open' path

        use command =
            Store.run
                connection
                ("select "
                 + columns
                 + " from studies where author_github_id = $id order by received_utc desc, id desc")
                [ "$id", box githubId ]

        use reader = command.ExecuteReader()

        [ while reader.Read() do
              readRecord reader ]

    let withdrawnReason = "withdrawn by the author"

    /// The author hides their own public study. True when it was hidden; another account's study is never touched.
    let withdraw (path: string) (now: DateTimeOffset) (githubId: int64) (id: string) : bool =
        use connection = open' path

        use command =
            Store.run
                connection
                "update studies set status = 'hidden', hidden_reason = $reason, hidden_utc = $now
                 where id = $id and author_github_id = $gid and status = 'public'"
                [ "$reason", box withdrawnReason
                  "$now", box (utc now)
                  "$id", box id
                  "$gid", box githubId ]

        command.ExecuteNonQuery() > 0

    // ---- the board ----------------------------------------------------------------------------------

    /// Studies of any status, newest first, for the board's command line.
    let listForBoard (path: string) (status: string option) (limit: int) : Record list =
        use connection = open' path

        use command =
            Store.run
                connection
                ("select "
                 + columns
                 + " from studies where ($status is null or status = $status)
                   order by received_utc desc, id desc limit $limit")
                [ "$status",
                  (match status with
                   | Some s -> box s
                   | None -> box DBNull.Value)
                  "$limit", box limit ]

        use reader = command.ExecuteReader()

        [ while reader.Read() do
              readRecord reader ]

    /// When the file of a study was deleted by the board, or `None`.
    let purgedUtc (path: string) (id: string) : string option =
        use connection = open' path

        match scalar connection "select purged_utc from studies where id = $id" [ "$id", box id ] with
        | :? string as t -> Some t
        | _ -> None

    /// Ids of the public studies that use the file of this hash, for the check before a purge.
    let publicWithHash (path: string) (sha256: string) : string list =
        use connection = open' path

        use command =
            Store.run
                connection
                "select id from studies where sha256 = $sha and status = 'public' order by id"
                [ "$sha", box sha256 ]

        use reader = command.ExecuteReader()

        [ while reader.Read() do
              reader.GetString 0 ]

    /// Marks every study of this hash as purged: they share one file on disk.
    let markPurged (path: string) (now: DateTimeOffset) (sha256: string) : unit =
        use connection = open' path

        use command =
            Store.run
                connection
                "update studies set purged_utc = $now where sha256 = $sha and purged_utc is null"
                [ "$now", box (utc now); "$sha", box sha256 ]

        command.ExecuteNonQuery() |> ignore

    /// The board republishes a hidden study. Refused (false) when its file was purged or when its author
    /// deleted the account: that author asked for the study to go.
    let unhide (path: string) (id: string) : bool =
        use connection = open' path

        use command =
            Store.run
                connection
                "update studies set status = 'public', hidden_reason = null, hidden_utc = null
                 where id = $id and status = 'hidden' and purged_utc is null and author_github_id > 0"
                [ "$id", box id ]

        command.ExecuteNonQuery() > 0

    type ReportRow =
        { Id: int64
          StudyId: string
          CreatedUtc: string
          Reason: string
          ClosedUtc: string option
          CloseNote: string option }

    /// Reports, oldest first, so the board answers in order.
    let listReports (path: string) (openOnly: bool) : ReportRow list =
        use connection = open' path

        use command =
            Store.run
                connection
                ("select id, study_id, created_utc, reason, closed_utc, close_note from reports "
                 + (if openOnly then "where closed_utc is null " else "")
                 + "order by id")
                []

        use reader = command.ExecuteReader()

        let opt i =
            if reader.IsDBNull i then None else Some(reader.GetString i)

        [ while reader.Read() do
              { Id = reader.GetInt64 0
                StudyId = reader.GetString 1
                CreatedUtc = reader.GetString 2
                Reason = reader.GetString 3
                ClosedUtc = opt 4
                CloseNote = opt 5 } ]

    /// True when an open report was closed.
    let closeReport (path: string) (now: DateTimeOffset) (id: int64) (note: string) : bool =
        use connection = open' path

        use command =
            Store.run
                connection
                "update reports set closed_utc = $now, close_note = $note where id = $id and closed_utc is null"
                [ "$now", box (utc now); "$note", box note; "$id", box id ]

        command.ExecuteNonQuery() > 0

    // ---- account deletion ---------------------------------------------------------------------------

    let accountDeletedReason = "account deleted by the author"

    /// Deletes the keys, the sessions and the account row. Every study of the account is hidden (the rows and
    /// the files stay) and detached: its author id becomes `-rowid`, which no GitHub id can be, and its login
    /// becomes `deleted`, so a later login with the same GitHub id starts with nothing. Reports keep their
    /// text and lose the reporter's id. All in one transaction. Returns the number of studies hidden now.
    let deleteAccount (path: string) (now: DateTimeOffset) (githubId: int64) : int =
        use connection = open' path
        use tx = connection.BeginTransaction()

        let exec sql parameters =
            use command = Store.run connection sql parameters
            command.Transaction <- tx
            command.ExecuteNonQuery()

        let id = [ "$id", box githubId ]

        let hidden =
            exec
                "update studies set status = 'hidden', hidden_reason = $reason, hidden_utc = $now
                 where author_github_id = $id and status = 'public'"
                [ "$reason", box accountDeletedReason
                  "$now", box (utc now)
                  "$id", box githubId ]

        exec "update studies set author_github_id = -rowid, author_login = 'deleted' where author_github_id = $id" id
        |> ignore

        exec "update reports set reporter_github_id = null where reporter_github_id = $id" id
        |> ignore

        exec "delete from api_keys where github_id = $id" id |> ignore
        exec "delete from sessions where github_id = $id" id |> ignore
        exec "delete from accounts where github_id = $id" id |> ignore
        tx.Commit()
        hidden

    /// A report of a study: the time and the reason, and nothing that names the reporter (no address, no account).
    let insertReport (path: string) (now: DateTimeOffset) (studyId: string) (reason: string) : bool =
        use connection = open' path

        use command =
            Store.run
                connection
                "insert into reports (study_id, created_utc, reason) select id, $now, $reason from studies where id = $id"
                [ "$now", box (utc now); "$reason", box reason; "$id", box studyId ]

        command.ExecuteNonQuery() > 0

    let countReports (path: string) (studyId: string) : int64 =
        use connection = open' path
        scalar connection "select count(*) from reports where study_id = $id" [ "$id", box studyId ] :?> int64
