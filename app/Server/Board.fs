namespace Marola.Server

open System
open System.Globalization
open System.IO
open System.Text
open Marola.Study

/// The board's command line, run over ssh: `marola-server studies ...` and `marola-server reports ...`.
/// Everything is plain lines. Text that a visitor wrote (a title, a report) goes through `clean` first, so
/// a hostile text cannot move the cursor, change the title of the terminal or forge a line of output.
/// Exit code: 0 done, 1 nothing changed (not found, already in that state, refused), 2 wrong usage.
module Board =

    let usage =
        String.concat
            "\n"
            [ "usage: marola-server studies list [--status public|hidden] [--limit n]"
              "       marola-server studies hide <id> --reason \"<text>\" [--purge]"
              "       marola-server studies unhide <id>"
              "       marola-server reports [--open]"
              "       marola-server reports close <report-id> --note \"<text>\""
              "exit code: 0 done, 1 nothing changed, 2 wrong usage" ]

    /// Replaces every control, format (for example the right-to-left override), line and paragraph
    /// separator, and unpaired surrogate with a space, so stored text is one safe line.
    let clean (text: string) : string =
        let sb = StringBuilder(text.Length)
        let mutable i = 0

        while i < text.Length do
            let c = text[i]

            if Char.IsHighSurrogate c && i + 1 < text.Length && Char.IsLowSurrogate text[i + 1] then
                sb.Append(c).Append(text[i + 1]) |> ignore
                i <- i + 2
            else
                match CharUnicodeInfo.GetUnicodeCategory c with
                | UnicodeCategory.Control
                | UnicodeCategory.Format
                | UnicodeCategory.LineSeparator
                | UnicodeCategory.ParagraphSeparator
                | UnicodeCategory.Surrogate
                | UnicodeCategory.OtherNotAssigned
                | UnicodeCategory.PrivateUse -> sb.Append ' ' |> ignore
                | _ -> sb.Append c |> ignore

                i <- i + 1

        sb.ToString()

    let private shorten (n: int) (text: string) =
        let t = clean text

        if t.Length <= n then t else t.Substring(0, n - 1) + "…"

    let private reasonMin, reasonMax = 5, 300
    let private noteMin, noteMax = 3, 300

    /// `--name value` pairs and bare words. An unknown option or a missing value is `None`.
    let private parse (known: string list) (flags: string list) (args: string list) =
        let rec go (words: string list) (opts: Map<string, string>) (set: Set<string>) args =
            match args with
            | [] -> Some(List.rev words, opts, set)
            | a :: rest when List.contains a flags -> go words opts (Set.add a set) rest
            | a :: v :: rest when List.contains a known -> go words (Map.add a v opts) set rest
            | a :: _ when a.StartsWith "--" -> None
            | w :: rest -> go (w :: words) opts set rest

        go [] Map.empty Set.empty args

    let private line (r: Record) (reports: int64) =
        let s = r.Submission

        let hidden =
            match r.Status, r.HiddenUtc, r.HiddenReason with
            | Hidden, Some t, Some why -> "  hidden " + t + ": " + shorten 120 why
            | Hidden, _, _ -> "  hidden"
            | _ -> ""

        $"{r.Id}  {statusName r.Status}  {r.ReceivedUtc}  {areaName s.Area}/{topicName s.Topic}  reports {reports}  @{shorten 40 r.AuthorLogin}  {shorten 80 s.Title}{hidden}"

    let private studies
        (config: Config)
        (now: DateTimeOffset)
        (args: string list)
        (out: TextWriter)
        (err: TextWriter)
        : int =
        let bad () =
            err.WriteLine usage
            2

        match args with
        | "list" :: rest ->
            match parse [ "--status"; "--limit" ] [] rest with
            | Some([], opts, _) ->
                let status = Map.tryFind "--status" opts
                let limit = Map.tryFind "--limit" opts |> Option.map Int32.TryParse

                match status, limit with
                | Some s, _ when s <> "public" && s <> "hidden" -> bad ()
                | _, Some(false, _) -> bad ()
                | _, Some(true, n) when n < 1 || n > 1000 -> bad ()
                | _ ->
                    StudyStore.migrate config.Db

                    let n =
                        match limit with
                        | Some(_, n) -> n
                        | None -> 50

                    for r in StudyStore.listForBoard config.Db status n do
                        out.WriteLine(line r (StudyStore.countReports config.Db r.Id))

                    0
            | _ -> bad ()
        | "hide" :: rest ->
            match parse [ "--reason" ] [ "--purge" ] rest with
            | Some([ id ], opts, flags) ->
                let reason =
                    Map.tryFind "--reason" opts |> Option.map (clean >> (fun s -> s.Trim()))

                match reason with
                | Some r when r.Length >= reasonMin && r.Length <= reasonMax ->
                    StudyStore.migrate config.Db

                    match StudyStore.getStudy config.Db id with
                    | None ->
                        err.WriteLine $"no study {shorten 20 id}"
                        1
                    | Some study ->
                        let purge = Set.contains "--purge" flags

                        let others =
                            StudyStore.publicWithHash config.Db study.Sha256 |> List.filter ((<>) id)

                        if purge && not others.IsEmpty then
                            // One file serves every study of the same bytes; deleting it would break the others.
                            err.WriteLine(
                                "other public studies use the same file: "
                                + String.concat ", " others
                                + ". Hide them too, then purge. Nothing changed."
                            )

                            1
                        elif study.Status = Hidden && not purge then
                            err.WriteLine $"{id} is hidden already"
                            1
                        else
                            if study.Status = Public then
                                StudyStore.hide config.Db now id r |> ignore
                                out.WriteLine $"hidden {id}"

                            if purge then
                                let path = PdfIntake.pathOf config study.Sha256
                                let existed = File.Exists path
                                File.Delete path
                                StudyStore.markPurged config.Db now study.Sha256
                                let what = if existed then "file deleted" else "no file on disk"
                                // The board writes this line in its record: a restore of a backup brings the file back.
                                out.WriteLine $"purged {study.Sha256} ({what}) at {StudyStore.utc now}"

                            0
                | _ ->
                    err.WriteLine $"--reason is required: {reasonMin} to {reasonMax} characters"
                    2
            | _ -> bad ()
        | [ "unhide"; id ] ->
            StudyStore.migrate config.Db

            match StudyStore.getStudy config.Db id with
            | None ->
                err.WriteLine $"no study {shorten 20 id}"
                1
            | Some _ when (StudyStore.purgedUtc config.Db id).IsSome ->
                err.WriteLine $"{id}: the file was purged, so it cannot be shown again"
                1
            | Some _ when StudyStore.unhide config.Db id ->
                out.WriteLine $"public {id}"
                0
            | Some s when s.Status = Public ->
                err.WriteLine $"{id} is public already"
                1
            | Some _ ->
                err.WriteLine $"{id}: the author deleted the account, so it cannot be shown again"
                1
        | _ -> bad ()

    let private reports
        (config: Config)
        (now: DateTimeOffset)
        (args: string list)
        (out: TextWriter)
        (err: TextWriter)
        : int =
        let bad () =
            err.WriteLine usage
            2

        match args with
        | "close" :: rest ->
            match parse [ "--note" ] [] rest with
            | Some([ id ], opts, _) ->
                let note = Map.tryFind "--note" opts |> Option.map (clean >> (fun s -> s.Trim()))

                match Int64.TryParse id, note with
                | (true, n), Some text when text.Length >= noteMin && text.Length <= noteMax ->
                    StudyStore.migrate config.Db

                    if StudyStore.closeReport config.Db now n text then
                        out.WriteLine $"closed #{n}"
                        0
                    else
                        err.WriteLine $"no open report #{n}"
                        1
                | (true, _), _ ->
                    err.WriteLine $"--note is required: {noteMin} to {noteMax} characters"
                    2
                | _ -> bad ()
            | _ -> bad ()
        | _ ->
            match parse [] [ "--open" ] args with
            | Some([], _, flags) ->
                StudyStore.migrate config.Db

                for r in StudyStore.listReports config.Db (Set.contains "--open" flags) do
                    let state =
                        match r.ClosedUtc, r.CloseNote with
                        | Some t, Some note -> "closed " + t + ": " + shorten 120 note
                        | Some t, None -> "closed " + t
                        | None, _ -> "open"

                    out.WriteLine $"#{r.Id}  {r.CreatedUtc}  study {shorten 20 r.StudyId}  {state}"
                    out.WriteLine $"    {shorten 1000 r.Reason}"

                0
            | _ -> bad ()

    let run (config: Config) (now: DateTimeOffset) (args: string list) (out: TextWriter) (err: TextWriter) : int =
        match args with
        | ("studies" | "reports") :: _ when not (File.Exists config.Db) ->
            err.WriteLine "there is no database yet: nothing to read"
            1
        | "studies" :: rest -> studies config now rest out err
        | "reports" :: rest -> reports config now rest out err
        | _ ->
            err.WriteLine usage
            2
