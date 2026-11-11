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
    /// stream is a false positive. The inflated bytes of a compressed object stream are scanned the same way
    /// (`ObjStmFinder` and `scanObjStms` below); plain streams (images, fonts) are not scanned inside.
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
    /// `Encrypted` is true when the name `/Encrypt` was seen: the file cannot be scanned. `TakeObjStm`
    /// tells once for each `/ObjStm` name; the finder uses it as its start signal.
    type NameScanner() =
        let name = Array.zeroCreate<byte> 32
        let mutable inName = false
        let mutable length = 0
        let mutable pendingOpenAction = false
        let mutable encrypted = false
        let mutable objStm = false
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
                elif n = "Encrypt" then
                    encrypted <- true
                elif n = "ObjStm" then
                    objStm <- true

                inName <- false
                length <- 0

        member _.Found = found
        member _.Encrypted = encrypted

        member _.TakeObjStm() =
            let seen = objStm
            objStm <- false
            seen

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

    /// Finds the compressed object streams while the file is read, without parsing PDF. A `/ObjStm` name
    /// starts a search for the next `stream` keyword. The text from the last `<<` before it to the keyword
    /// must match a strict dictionary grammar (below), and the `<<` must follow an `N G obj` that starts a
    /// line (a comment ends at the line, so the `<<` is not inside one). The grammar has no string,
    /// comment, array or nested dictionary, so a spoofed `<<` or a second filter cannot hide in it.
    /// Anything else is `Refusal`: false positives cost less than an exploit. A stream with `/Filter
    /// /FlateDecode` gets its start offset in `Offsets` (the first byte after the white space that follows
    /// the keyword; a zlib header never starts with white space). A stream with no filter is plain bytes the
    /// name scan has seen already.
    type ObjStmFinder() =
        let ringSize = 1024
        let maxAfter = 600
        let maxStreams = 10000
        let ring = Array.zeroCreate<byte> ringSize
        let mutable ringLength = 0
        let mutable ringNext = 0
        let after = Collections.Generic.List<byte>()
        let mutable head = ""
        let mutable pending = false
        let mutable skipping = false
        let mutable position = 0L
        let offsets = Collections.Generic.List<int64>()
        let mutable refusal: string option = None

        let ws = @"[ \t\r\n\f\x00]"

        let grammar =
            Text.RegularExpressions.Regex(
                "^<<(?:"
                + String.Join(
                    "|",
                    [ ws + "*/Type" + ws + "*/ObjStm"
                      ws + "*/N" + ws + @"+\d+"
                      ws + "*/First" + ws + @"+\d+"
                      ws + "*/Length" + ws + @"+\d+(?:" + ws + @"+\d+" + ws + "+R)?"
                      ws + "*/Extends" + ws + @"+\d+" + ws + @"+\d+" + ws + "+R"
                      ws + "*/Filter" + ws + "*/FlateDecode" ]
                )
                + ")*"
                + ws
                + "*>>"
                + ws
                + "*stream$",
                Text.RegularExpressions.RegexOptions.CultureInvariant,
                TimeSpan.FromSeconds 1.0
            )

        let objHeader =
            Text.RegularExpressions.Regex(
                "[\r\n]" + ws + @"*\d+" + ws + @"+\d+" + ws + "+obj" + ws + "*$",
                Text.RegularExpressions.RegexOptions.CultureInvariant,
                TimeSpan.FromSeconds 1.0
            )

        let latin1 (bytes: seq<byte>) =
            Text.Encoding.Latin1.GetString(Seq.toArray bytes)

        let check () =
            let text = head + latin1 after
            let start = text.LastIndexOf("<<", StringComparison.Ordinal)

            if start < 0 then
                refusal <- Some "an object stream has no dictionary the scan can read"
            else
                let before = text.Substring(0, start)
                let dict = text.Substring start

                if
                    not (objHeader.IsMatch before)
                    || not (dict.Contains "/ObjStm")
                    || not (grammar.IsMatch dict)
                then
                    refusal <- Some "an object stream has a dictionary the scan cannot check"
                elif dict.Contains "/Filter" then
                    if offsets.Count >= maxStreams then
                        refusal <- Some "the file has too many object streams to scan"
                    else
                        skipping <- true

        member _.Refusal = refusal
        member _.Offsets = offsets

        /// `armed` is `NameScanner.TakeObjStm()` after the scanner saw the same byte.
        member _.Feed(b: byte, armed: bool) =
            position <- position + 1L

            if refusal.IsNone then
                if skipping then
                    if not (isSpace b) then
                        offsets.Add(position - 1L)
                        skipping <- false
                elif pending then
                    after.Add b

                    if after.Count > maxAfter then
                        refusal <- Some "an object stream has no stream keyword near its name"
                        pending <- false
                    elif after.Count >= 6 && latin1 (after.GetRange(after.Count - 6, 6)) = "stream" then
                        pending <- false
                        check ()

                ring[ringNext] <- b
                ringNext <- (ringNext + 1) % ringSize
                ringLength <- min ringSize (ringLength + 1)

                if armed && not pending && not skipping then
                    let start = (ringNext - ringLength + ringSize) % ringSize
                    head <- latin1 (Seq.init ringLength (fun i -> ring[(start + i) % ringSize]))
                    after.Clear()
                    pending <- true

    /// Reads a stream and remembers that it ended before the consumer did: the inflater asked for more and
    /// got none, so the compressed data was cut short.
    type private Probe(inner: Stream) =
        inherit Stream()
        member val HitEnd = false with get, set
        override _.CanRead = true
        override _.CanSeek = false
        override _.CanWrite = false
        override _.Length = raise (NotSupportedException())

        override _.Position
            with get () = raise (NotSupportedException())
            and set _ = raise (NotSupportedException())

        override _.Flush() = ()
        override _.Seek(_, _) = raise (NotSupportedException())
        override _.SetLength _ = raise (NotSupportedException())
        override _.Write(_, _, _) = raise (NotSupportedException())

        override this.Read(buffer: byte[], offset: int, count: int) =
            let n = inner.Read(buffer, offset, count)

            if n = 0 then
                this.HitEnd <- true

            n

    let private perStreamCap = 32L * 1024L * 1024L
    let private perFileCap = 128L * 1024L * 1024L

    type Received =
        {
            Sha256: string
            Size: int64
            /// The temp file, or `None` on a dry run.
            Temp: string option
        }

    /// A failure is a field error on `pdf`: `too_large` (413), `not_pdf`, `truncated`, `active_content`,
    /// `pdf_encrypted` or `pdf_unscannable` (400).
    let private fail code message : FieldError =
        { Field = "pdf"
          Code = code
          Message = message }

    /// `Some` when a compressed object stream cannot be scanned or holds active content. Inflates each stream
    /// from `file` in 64 KB pieces and feeds them to a `NameScanner`; the output is never kept, and the caps
    /// stop a zip bomb after 32 MB of one stream or 128 MB of the file.
    let private scanObjStms (file: FileStream) (offsets: seq<int64>) : FieldError option =
        let buffer = Array.zeroCreate<byte> 65536
        let mutable total = 0L
        let mutable failure: FieldError option = None

        let unscannable why =
            fail "pdf_unscannable" (why + ", so marola cannot check it")

        for offset in offsets do
            if failure.IsNone then
                file.Seek(offset, SeekOrigin.Begin) |> ignore
                let probe = new Probe(file)

                use inflater =
                    new Compression.ZLibStream(probe, Compression.CompressionMode.Decompress, true)

                let scanner = NameScanner()
                let mutable size = 0L
                let mutable reading = true

                try
                    while reading && failure.IsNone do
                        let n = inflater.Read(buffer, 0, buffer.Length)

                        if n = 0 then
                            reading <- false
                        else
                            size <- size + int64 n
                            total <- total + int64 n

                            if size > perStreamCap || total > perFileCap then
                                failure <- Some(unscannable "an object stream inflates to more than the scan allows")
                            else
                                for i in 0 .. n - 1 do
                                    scanner.Feed buffer[i]
                with :? InvalidDataException ->
                    failure <- Some(unscannable "an object stream does not inflate")

                if failure.IsNone then
                    scanner.Finish()

                    match scanner.Found with
                    | Some name ->
                        failure <-
                            Some(fail "active_content" ("the file contains " + name + ", which marola does not host"))
                    | None ->
                        if probe.HitEnd then
                            failure <- Some(unscannable "an object stream is cut short")

        failure

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

    /// Streams `input`. `store = false` is a dry run: it stores nothing under `MAROLA_STUDIES`.
    let receive (config: Config) (store: bool) (input: Stream) : Task<Result<Received, FieldError>> =
        task {
            let buffer = Array.zeroCreate<byte> 65536
            let tail = Array.zeroCreate<byte> tailSize
            let mutable tailLength = 0
            let mutable total = 0L
            let mutable first5 = [||]
            let scanner = NameScanner()
            let finder = ObjStmFinder()
            use hash = IncrementalHash.CreateHash HashAlgorithmName.SHA256
            let mutable temp: string option = None
            let mutable output: FileStream = null
            let mutable failure: FieldError option = None

            try
                // The file is always written: the compressed object streams are inflated from it after the
                // last byte is read. A dry run uses a private temp file that the system deletes on close.
                if store then
                    ensureDirs config
                    let path = Path.Combine(incoming config, Guid.NewGuid().ToString "N")

                    let options =
                        FileStreamOptions(
                            Mode = FileMode.CreateNew,
                            Access = FileAccess.ReadWrite,
                            Share = FileShare.None,
                            Options = FileOptions.Asynchronous,
                            UnixCreateMode =
                                Nullable(UnixFileMode.UserRead ||| UnixFileMode.UserWrite ||| UnixFileMode.GroupRead)
                        )

                    output <- new FileStream(path, options)
                    temp <- Some path
                else
                    let options =
                        FileStreamOptions(
                            Mode = FileMode.CreateNew,
                            Access = FileAccess.ReadWrite,
                            Share = FileShare.None,
                            Options = (FileOptions.Asynchronous ||| FileOptions.DeleteOnClose),
                            UnixCreateMode = Nullable(UnixFileMode.UserRead ||| UnixFileMode.UserWrite)
                        )

                    output <-
                        new FileStream(
                            Path.Combine(Path.GetTempPath(), "marola-dry-" + Guid.NewGuid().ToString "N"),
                            options
                        )

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
                                finder.Feed(buffer[i], scanner.TakeObjStm())

                            if n >= tailSize then
                                Array.blit buffer (n - tailSize) tail 0 tailSize
                                tailLength <- tailSize
                            else
                                let keep = min tailLength (tailSize - n)
                                Array.blit tail (tailLength - keep) tail 0 keep
                                Array.blit buffer 0 tail keep n
                                tailLength <- keep + n

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
                        | None ->
                            if scanner.Encrypted then
                                failure <-
                                    Some(
                                        fail
                                            "pdf_encrypted"
                                            "the file is encrypted, so marola cannot check what it contains"
                                    )
                            else
                                match finder.Refusal with
                                | Some why ->
                                    failure <- Some(fail "pdf_unscannable" (why + ", so marola cannot check it"))
                                | None ->
                                    do! output.FlushAsync()
                                    failure <- scanObjStms output finder.Offsets

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
