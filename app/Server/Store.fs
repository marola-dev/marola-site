namespace Marola.Server

open System
open System.IO
open Microsoft.Data.Sqlite

/// The contact messages: one SQLite file, one table. Statements are constants with bound parameters.
module Store =

    type Message =
        { Id: int64
          CreatedUtc: string
          Email: string
          Body: string }

    let internal connect (mode: SqliteOpenMode) (path: string) : SqliteConnection =
        let builder = SqliteConnectionStringBuilder()
        builder.DataSource <- path
        builder.Mode <- mode
        let connection = new SqliteConnection(builder.ToString())
        connection.Open()
        connection

    let internal run (connection: SqliteConnection) (sql: string) (parameters: (string * obj) list) =
        let command = connection.CreateCommand()
        command.CommandText <- sql

        for (name, value) in parameters do
            command.Parameters.AddWithValue(name, value) |> ignore

        command

    /// Creates the folder, the file and the table when they are missing.
    let init (path: string) : unit =
        Directory.CreateDirectory(Path.GetDirectoryName(path: string)) |> ignore
        use connection = connect SqliteOpenMode.ReadWriteCreate path

        use command =
            run
                connection
                "create table if not exists messages (id integer primary key autoincrement, created_utc text not null, email text not null, body text not null)"
                []

        command.ExecuteNonQuery() |> ignore

    let insert (path: string) (now: DateTimeOffset) (email: string) (body: string) : int64 =
        use connection = connect SqliteOpenMode.ReadWrite path

        use command =
            run
                connection
                "insert into messages (created_utc, email, body) values ($created, $email, $body) returning id"
                [ "$created", box (now.UtcDateTime.ToString "yyyy-MM-ddTHH:mm:ssZ")
                  "$email", box email
                  "$body", box body ]

        command.ExecuteScalar() :?> int64

    /// Oldest first. A missing file is an empty inbox: reading must not create the database.
    let list (path: string) : Message list =
        if not (File.Exists path) then
            []
        else
            use connection = connect SqliteOpenMode.ReadOnly path

            use command =
                run connection "select id, created_utc, email, body from messages order by id" []

            use reader = command.ExecuteReader()

            [ while reader.Read() do
                  { Id = reader.GetInt64 0
                    CreatedUtc = reader.GetString 1
                    Email = reader.GetString 2
                    Body = reader.GetString 3 } ]

    /// True when a row was deleted.
    let delete (path: string) (id: int64) : bool =
        if not (File.Exists path) then
            false
        else
            use connection = connect SqliteOpenMode.ReadWrite path
            use command = run connection "delete from messages where id = $id" [ "$id", box id ]
            command.ExecuteNonQuery() > 0
