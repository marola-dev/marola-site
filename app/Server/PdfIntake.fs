namespace Marola.Server

open System
open System.IO
open System.Security.Cryptography
open System.Threading.Tasks
open Marola.Study

/// Takes a PDF from a stream: counts it, hashes it, checks it and, unless it is a dry run, writes it to a
/// temp file. The bytes are never held in memory as a whole. Storing under the hash is `commit`.
module PdfIntake =

    let maxBytes = 20L * 1024L * 1024L

    /// `%%EOF` and `startxref` must sit in the last 1024 bytes: a file cut short does not.
    let private tailSize = 1024

    /// The names of active content. The rule, exactly: scan every byte of the file for a PDF name (a `/`
    /// and the regular characters after it, with `#xx` escapes decoded, so `/J#53` is `/JS`); the file
    /// is refused when a name is one of these, anywhere, in a stream too. `/OpenAction` is refused only
    /// when its value is not a destination array, an indirect reference or null: `/OpenAction << ... >>`
    /// is an action, `/OpenAction [3 0 R /Fit]` is the page a reader opens on. A match inside a compressed
    /// stream is a false positive; an action inside a compressed object stream is not seen (see ADR 0004).
    let forbiddenNames = [ "Launch"; "JavaScript"; "JS"; "EmbeddedFile" ]

    let private isSpace (b: byte) =
        b = 0uy || b = 9uy || b = 10uy || b = 12uy || b = 13uy || b = 32uy

    let private isDelimiter (b: byte) =
        match char b with
        | '('
        | ')'
        | '<'
        | '>'
        | '['
        | ']'
        | '{'
        | '}'
        | '/'
        | '%' -> true
        | _ -> false

    let private hexValue (b: byte) =
        match char b with
        | c when c >= '0' && c <= '9' -> int c - int '0'
        | c when c >= 'a' && c <= 'f' -> int c - int 'a' + 10
        | c when c >= 'A' && c <= 'F' -> int c - int 'A' + 10
        | _ -> -1

    /// Reads names byte by byte, across chunk borders. `Found` is the first forbidden thing it saw.
    type NameScanner() =
        let name = Array.zeroCreate<byte> 32
        let mutable inName = false
        let mutable length = 0
        let mutable pendingOpenAction = false
        let mutable found: string option = None

        let decoded () : string =
            // A name longer than the buffer is no name on the list; "" matches nothing.
            if length > name.Length then
                ""
            else
                let chars = Collections.Generic.List<char>()
                let mutable i = 0

                while i < length do
                    if
                        name[i] = byte '#'
                        && i + 2 < length
                        && hexValue name[i + 1] >= 0
                        && hexValue name[i + 2] >= 0
                    then
                        chars.Add(char (hexValue name[i + 1] * 16 + hexValue name[i + 2]))
                        i <- i + 3
                    else
                        chars.Add(char name[i])
                        i <- i + 1

                String(chars.ToArray())

        let finishName () =
            if inName then
                let n = decoded ()

                if List.contains n forbiddenNames then
                    found <- Some("/" + n)
                elif n = "OpenAction" then
                    pendingOpenAction <- true

                inName <- false
                length <- 0

        member _.Found = found

        member _.Feed(b: byte) =
            if found.IsNone then
                if inName then
                    if isSpace b || isDelimiter b then
                        finishName ()
                    else
                        if length < name.Length then
                            name[length] <- b

                        length <- length + 1

                // Not an `else`: the byte that ends a name is also the next byte after it.
                if not inName then
                    if pendingOpenAction && not (isSpace b) then
                        pendingOpenAction <- false

                        let ok = b = byte '[' || (b >= byte '0' && b <= byte '9') || b = byte 'n'

                        if not ok then
                            found <- Some "/OpenAction with an action"

                    if b = byte '/' then
                        inName <- true
                        length <- 0

        member this.Finish() =
            finishName ()
            pendingOpenAction <- false

    type Received =
        {
            Sha256: string
            Size: int64
            /// The temp file, or `None` on a dry run.
            Temp: string option
        }

    /// A failure is a field error on `pdf`: `too_large` (413), `not_pdf`, `truncated` or `active_content` (400).
    let private fail code message : FieldError =
        { Field = "pdf"
          Code = code
          Message = message }

    let private incoming (config: Config) =
        Path.Combine(config.Studies, ".incoming")

    let private ensureDirs (config: Config) =
        let mode =
            UnixFileMode.UserRead
            ||| UnixFileMode.UserWrite
            ||| UnixFileMode.UserExecute
            ||| UnixFileMode.GroupRead
            ||| UnixFileMode.GroupExecute

        Directory.CreateDirectory(config.Studies, mode) |> ignore
        Directory.CreateDirectory(incoming config, mode) |> ignore

    /// The path of a stored file, built from a hash that passed `validSha256` and nothing else.
    let pathOf (config: Config) (sha256: string) : string =
        if not (validSha256 sha256) then
            invalidArg "sha256" "not a SHA-256"

        Path.Combine(config.Studies, sha256 + ".pdf")

    /// Streams `input`. `store = false` is a dry run: nothing is created on disk.
    let receive (config: Config) (store: bool) (input: Stream) : Task<Result<Received, FieldError>> =
        task {
            let buffer = Array.zeroCreate<byte> 65536
            let tail = Array.zeroCreate<byte> tailSize
            let mutable tailLength = 0
            let mutable total = 0L
            let mutable first5 = [||]
            let scanner = NameScanner()
            use hash = IncrementalHash.CreateHash HashAlgorithmName.SHA256
            let mutable temp: string option = None
            let mutable output: FileStream = null
            let mutable failure: FieldError option = None

            try
                if store then
                    ensureDirs config
                    let path = Path.Combine(incoming config, Guid.NewGuid().ToString "N")

                    let options =
                        FileStreamOptions(
                            Mode = FileMode.CreateNew,
                            Access = FileAccess.Write,
                            Share = FileShare.None,
                            Options = FileOptions.Asynchronous,
                            UnixCreateMode =
                                Nullable(UnixFileMode.UserRead ||| UnixFileMode.UserWrite ||| UnixFileMode.GroupRead)
                        )

                    output <- new FileStream(path, options)
                    temp <- Some path

                let mutable reading = true

                while reading && failure.IsNone do
                    let! n = input.ReadAsync(buffer, 0, buffer.Length)

                    if n = 0 then
                        reading <- false
                    else
                        total <- total + int64 n

                        if total > maxBytes then
                            failure <-
                                Some(
                                    fail "too_large" ("the file is larger than " + string (maxBytes / 1048576L) + " MB")
                                )
                        else
                            if first5.Length < 5 then
                                first5 <- Array.append first5 buffer[0 .. (min n (5 - first5.Length)) - 1]

                            hash.AppendData(buffer, 0, n)

                            for i in 0 .. n - 1 do
                                scanner.Feed buffer[i]

                            if n >= tailSize then
                                Array.blit buffer (n - tailSize) tail 0 tailSize
                                tailLength <- tailSize
                            else
                                let keep = min tailLength (tailSize - n)
                                Array.blit tail (tailLength - keep) tail 0 keep
                                Array.blit buffer 0 tail keep n
                                tailLength <- keep + n

                            if not (isNull output) then
                                do! output.WriteAsync(buffer, 0, n)

                scanner.Finish()

                if failure.IsNone then
                    let tailText = Text.Encoding.Latin1.GetString(tail, 0, tailLength)

                    if first5 <> "%PDF-"B then
                        failure <- Some(fail "not_pdf" "the file does not start with %PDF-")
                    elif not (tailText.Contains "%%EOF") || not (tailText.Contains "startxref") then
                        failure <-
                            Some(fail "truncated" "the file has no startxref and %%EOF at its end: it looks cut short")
                    else
                        match scanner.Found with
                        | Some name ->
                            failure <-
                                Some(
                                    fail "active_content" ("the file contains " + name + ", which marola does not host")
                                )
                        | None -> ()

                if not (isNull output) then
                    do! output.FlushAsync()
                    output.Dispose()
                    output <- null

                match failure with
                | Some f ->
                    temp |> Option.iter (fun p -> File.Delete p)
                    return Error f
                | None ->
                    let sha = Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant()

                    return
                        Ok
                            { Sha256 = sha
                              Size = total
                              Temp = temp }
            with e ->
                if not (isNull output) then
                    output.Dispose()

                temp
                |> Option.iter (fun p ->
                    try
                        File.Delete p
                    with _ ->
                        ())

                return raise e
        }

    /// Bytes the stored PDFs take now.
    let used (config: Config) : int64 =
        if Directory.Exists config.Studies then
            Directory.EnumerateFiles(config.Studies, "*.pdf")
            |> Seq.sumBy (fun f -> FileInfo(f).Length)
        else
            0L

    /// True when storing a file of this hash and size would pass the quota. A file already stored costs nothing.
    let fitsQuota (config: Config) (r: Received) : bool =
        File.Exists(pathOf config r.Sha256)
        || used config + r.Size <= config.StudiesQuota

    /// Moves the temp file to `<sha256>.pdf`. The hash names the file, so the same bytes are written once.
    let commit (config: Config) (r: Received) : unit =
        match r.Temp with
        | None -> ()
        | Some temp ->
            let final = pathOf config r.Sha256

            if File.Exists final then
                File.Delete temp
            else
                File.Move(temp, final)

    let discard (r: Received) : unit =
        r.Temp |> Option.iter (fun p -> File.Delete p)
