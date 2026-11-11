module Marola.Server.Tests.PdfTests

open System
open System.IO
open System.Security.Cryptography
open System.Text
open Expecto
open Marola.Server

/// A tiny PDF: header, one object, trailer, `startxref` and `%%EOF`. `extra` goes into the catalog,
/// `padding` bytes of comment make it as long as a test needs.
let pdfBytes (extra: string) (padding: int) : byte[] =
    let body =
        "%PDF-1.4\n"
        + (if padding > 0 then
               "%" + String('x', padding) + "\n"
           else
               "")
        + "1 0 obj\n<< /Type /Catalog /Pages 2 0 R "
        + extra
        + " >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\ntrailer\n<< /Root 1 0 R >>\nstartxref\n9\n%%EOF\n"

    Encoding.Latin1.GetBytes body

let validPdf = pdfBytes "" 0

let sha (bytes: byte[]) =
    Convert.ToHexString(SHA256.HashData bytes).ToLowerInvariant()

let withConfig (quota: int64) (body: Config -> unit) =
    let root =
        Path.Combine(Path.GetTempPath(), "marola-pdf-" + Guid.NewGuid().ToString "N")

    let config: Config =
        { Port = 0
          Static = ""
          Data = ""
          Db = Path.Combine(root, "db", "marola.db")
          Studies = Path.Combine(root, "studies")
          StudiesQuota = quota
          Dev = false
          GithubClientId = Some "test-client-id"
          GithubSecretFile = None
          GithubBase = "https://github.test"
          GithubApiBase = "https://api.github.test" }

    try
        body config
    finally
        if Directory.Exists root then
            Directory.Delete(root, true)

let receive config store (bytes: byte[]) =
    use stream = new MemoryStream(bytes)
    (PdfIntake.receive config store stream).Result

let codeOf (r: Result<PdfIntake.Received, Marola.Study.FieldError>) =
    match r with
    | Ok _ -> "ok"
    | Error e -> e.Code

/// A stream of zeros that never exists in memory, to prove the limit is applied while reading.
type Endless(length: int64) =
    inherit Stream()
    let mutable position = 0L
    member _.Position' = position
    override _.CanRead = true
    override _.CanSeek = false
    override _.CanWrite = false
    override _.Length = length

    override _.Position
        with get () = position
        and set _ = ()

    override _.Flush() = ()
    override _.Seek(_, _) = raise (NotSupportedException())
    override _.SetLength _ = ()
    override _.Write(_, _, _) = ()

    override _.Read(buffer: byte[], offset: int, count: int) =
        let n = int (min (int64 count) (length - position))
        Array.fill buffer offset n 0uy
        position <- position + int64 n
        n

let private files (config: Config) =
    if Directory.Exists config.Studies then
        Directory.GetFiles(config.Studies, "*", SearchOption.AllDirectories)
    else
        [||]

let tests =
    testList
        "pdf intake"
        [ test "a valid file is hashed while it streams, written 0640 to a temp file and moved to <sha256>.pdf" {
              withConfig 10_000_000L (fun config ->
                  // 200 KB: three chunks, so the hash and the tail window cross chunk borders.
                  let bytes = pdfBytes "" 200_000

                  match receive config true bytes with
                  | Error e -> failtest e.Message
                  | Ok r ->
                      Expect.equal r.Sha256 (sha bytes) "hash"
                      Expect.equal r.Size (int64 bytes.Length) "size"
                      let temp = r.Temp.Value
                      Expect.isTrue (File.Exists temp) "temp"
                      let mode = File.GetUnixFileMode temp

                      Expect.equal
                          (mode
                           &&& (UnixFileMode.GroupWrite
                                ||| UnixFileMode.OtherRead
                                ||| UnixFileMode.OtherWrite
                                ||| UnixFileMode.OtherExecute))
                          UnixFileMode.None
                          "no write for the group, nothing for others"

                      Expect.equal (mode &&& UnixFileMode.UserRead) UnixFileMode.UserRead "owner reads"
                      PdfIntake.commit config r
                      let final = PdfIntake.pathOf config r.Sha256
                      Expect.isTrue (File.Exists final) "final"
                      Expect.isFalse (File.Exists temp) "temp gone"
                      Expect.equal (File.ReadAllBytes final) bytes "same bytes"
                      // The same bytes again: one file.
                      let again =
                          (receive config true bytes) |> Result.defaultWith (fun e -> failtest e.Message)

                      PdfIntake.commit config again
                      Expect.equal (files config |> Array.length) 1 "one file")
          }

          test "a dry run creates no file and no folder" {
              withConfig 10_000_000L (fun config ->
                  match receive config false validPdf with
                  | Ok r ->
                      Expect.isNone r.Temp "no temp"
                      Expect.equal r.Sha256 (sha validPdf) "hash"
                      Expect.isFalse (Directory.Exists config.Studies) "no folder"
                  | Error e -> failtest e.Message)
          }

          test "bad magic, empty and truncated files are refused and leave nothing" {
              withConfig 10_000_000L (fun config ->
                  Expect.equal (codeOf (receive config true "PK\u0003\u0004 not a pdf"B)) "not_pdf" "zip"
                  Expect.equal (codeOf (receive config true [||])) "not_pdf" "empty"

                  Expect.equal
                      (codeOf (receive config true (" %PDF-1.4"B |> Array.append [||])))
                      "not_pdf"
                      "space before magic"

                  Expect.equal
                      (codeOf (receive config true validPdf[.. validPdf.Length - 20]))
                      "truncated"
                      "cut at the end"

                  Expect.equal
                      (codeOf (receive config true (Encoding.Latin1.GetBytes "%PDF-1.4\n1 0 obj\n<< >>\n")))
                      "truncated"
                      "no trailer"

                  Expect.isEmpty (files config) "no file is left")
          }

          test "active content is refused: names, escaped names, and an OpenAction with an action" {
              withConfig 10_000_000L (fun config ->
                  let refused (extra: string) =
                      Expect.equal (codeOf (receive config true (pdfBytes extra 0))) "active_content" extra

                  refused "/AA << /O << /S /JavaScript /JS (app.alert(1)) >> >>"
                  refused "/JS (app.alert(1))"
                  refused "/JS(app.alert(1))"
                  refused "/S /Launch /F (cmd.exe)"
                  refused "/Names << /EmbeddedFiles << >> >> /Type /EmbeddedFile"
                  refused "/OpenAction << /S /URI /URI (https://evil.example) >>"
                  refused "/OpenAction<</S/GoTo>>"
                  refused "/OpenAction /Foo"
                  refused "/J#53 (x)"
                  refused "/#4AavaScript"
                  refused "/#4a#61vaScript"
                  Expect.isEmpty (files config) "no file is left")
          }

          test "plain PDFs with a destination OpenAction, a reference or a similar name are accepted" {
              withConfig 10_000_000L (fun config ->
                  for extra in
                      [ "/OpenAction [3 0 R /Fit]"
                        "/OpenAction 5 0 R"
                        "/OpenAction null"
                        "/OpenAction\n[3 0 R /XYZ 0 0 0]"
                        "/JSON 1 /JavaScripts 2 /Font /Arial#20Bold" ] do
                      Expect.equal (codeOf (receive config false (pdfBytes extra 0))) "ok" extra)
          }

          test "a forbidden name that straddles the 64 KB read border is found" {
              withConfig 10_000_000L (fun config ->
                  // The header is 9 bytes, padding then moves "/JavaScript" over the border at 65536.
                  let bytes = pdfBytes "/S /JavaScript" 0
                  let at = Encoding.Latin1.GetString(bytes).IndexOf "/JavaScript"

                  for shift in -3 .. 3 do
                      // The same file with the name at several offsets around the border.
                      let padding = 65536 - at + shift - 3
                      let moved = pdfBytes "/S /JavaScript" padding
                      Expect.equal (codeOf (receive config false moved)) "active_content" (sprintf "shift %d" shift))
          }

          test "a file over 20 MB is refused while streaming, without reading it all and without a file" {
              withConfig 100_000_000L (fun config ->
                  let source = new Endless(1_000_000_000L)
                  let result = (PdfIntake.receive config true source).Result
                  Expect.equal (codeOf result) "too_large" "413"
                  Expect.isLessThan source.Position' (PdfIntake.maxBytes + 200_000L) "it stopped reading"
                  Expect.isEmpty (files config) "no file is left")
          }

          test "a file of exactly 20 MB is not too large" {
              withConfig 100_000_000L (fun config ->
                  let padding = int PdfIntake.maxBytes - validPdf.Length - 2
                  let bytes = pdfBytes "" padding
                  Expect.equal (int64 bytes.Length) PdfIntake.maxBytes "the exact size"
                  Expect.equal (codeOf (receive config false bytes)) "ok" "ok")
          }

          test "the quota counts the stored bytes; a file already stored costs nothing" {
              withConfig (int64 validPdf.Length + 100L) (fun config ->
                  let first =
                      (receive config true validPdf)
                      |> Result.defaultWith (fun e -> failtest e.Message)

                  Expect.isTrue (PdfIntake.fitsQuota config first) "the first fits"
                  PdfIntake.commit config first
                  Expect.equal (PdfIntake.used config) (int64 validPdf.Length) "used"

                  let other =
                      (receive config false (pdfBytes "/Foo 1" 0))
                      |> Result.defaultWith (fun e -> failtest e.Message)

                  Expect.isFalse (PdfIntake.fitsQuota config other) "the second does not"

                  let again =
                      (receive config false validPdf)
                      |> Result.defaultWith (fun e -> failtest e.Message)

                  Expect.isTrue (PdfIntake.fitsQuota config again) "the same file again")
          }

          test "the stored path is built from a hash and refuses anything else" {
              withConfig 1L (fun config ->
                  Expect.throws (fun () -> PdfIntake.pathOf config "../../etc/passwd" |> ignore) "dots"
                  Expect.throws (fun () -> PdfIntake.pathOf config (String.replicate 63 "a") |> ignore) "short"
                  Expect.throws (fun () -> PdfIntake.pathOf config (String.replicate 64 "A") |> ignore) "upper case"

                  Expect.equal
                      (PdfIntake.pathOf config (String.replicate 64 "a"))
                      (Path.Combine(config.Studies, String.replicate 64 "a" + ".pdf"))
                      "ok")
          } ]

/// A zlib stream of `data`, as an object stream in a PDF has it.
let zlib (level: Compression.CompressionLevel) (data: byte[]) : byte[] =
    use memory = new MemoryStream()

    do
        use z = new Compression.ZLibStream(memory, level, true)
        z.Write(data, 0, data.Length)

    memory.ToArray()

/// `n` bytes of zero, compressed without ever holding them all.
let zlibZeros (n: int) : byte[] =
    use memory = new MemoryStream()

    do
        use z =
            new Compression.ZLibStream(memory, Compression.CompressionLevel.Fastest, true)

        let chunk = Array.zeroCreate<byte> 1_048_576

        for _ in 1 .. n / chunk.Length do
            z.Write(chunk, 0, chunk.Length)

    memory.ToArray()

/// A PDF with object streams: each `dict` is the dictionary of object `10 + i`, each body its stream data.
let objStmPdf (streams: (string * byte[]) list) : byte[] =
    let latin1 (s: string) = Encoding.Latin1.GetBytes s

    [ yield latin1 "%PDF-1.5\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
      for i, (dict, body) in List.indexed streams do
          yield latin1 (sprintf "%d 0 obj\n%s\nstream\n" (10 + i) dict)
          yield body
          yield latin1 "\nendstream\nendobj\n"
      yield latin1 "trailer\n<< /Root 1 0 R >>\nstartxref\n9\n%%EOF\n" ]
    |> Array.concat

let flateDict = "<</Type/ObjStm/N 1/First 4/Filter/FlateDecode/Length 99>>"

/// What an object stream holds: the pairs of number and offset, then the objects.
let inner (text: string) = Encoding.Latin1.GetBytes("5 0 " + text)

let objStmTests =
    testList
        "pdf object streams"
        [ test "an action inside a compressed object stream is refused, as in a plain one" {
              withConfig 10_000_000L (fun config ->
                  let pdf =
                      objStmPdf
                          [ flateDict,
                            zlib Compression.CompressionLevel.Optimal (inner "<< /S /JavaScript /JS (app.alert(1)) >>") ]

                  Expect.equal (codeOf (receive config true pdf)) "active_content" "stored run"
                  Expect.equal (codeOf (receive config false pdf)) "active_content" "dry run"

                  let escaped =
                      objStmPdf
                          [ flateDict,
                            zlib Compression.CompressionLevel.Optimal (inner "<< /S /Launch /F (cmd.exe) >>")
                            flateDict, zlib Compression.CompressionLevel.Optimal (inner "<< /J#53 (x) >>") ]

                  Expect.equal (codeOf (receive config true escaped)) "active_content" "second stream, escaped name"
                  Expect.isEmpty (files config) "no file is left")
          }

          test "a clean object stream is accepted, in the forms that Word, LaTeX and qpdf write" {
              withConfig 10_000_000L (fun config ->
                  let clean =
                      zlib
                          Compression.CompressionLevel.Optimal
                          (inner "<< /Type /Page /Parent 2 0 R /Contents 7 0 R /OpenAction [3 0 R /Fit] >>")

                  for dict in
                      [ flateDict
                        "<</Type/ObjStm/N 69/First 513/Filter/FlateDecode/Length 1531>>"
                        "<<\n/Type /ObjStm\n/N 2\n/First 10\n/Length 12 0 R\n/Filter /FlateDecode\n>>"
                        "<</Length 99/Filter/FlateDecode/Extends 3 0 R/First 4/N 1/Type/ObjStm>>"
                        "<<\r\n/Type /ObjStm /N 1 /First 4 /Filter /FlateDecode /Length 99 \r\n>>" ] do
                      let pdf = objStmPdf [ dict, clean ]
                      Expect.equal (codeOf (receive config false pdf)) "ok" dict

                      match receive config true pdf with
                      | Ok r ->
                          PdfIntake.commit config r
                          Expect.equal (File.ReadAllBytes(PdfIntake.pathOf config r.Sha256)) pdf "stored whole"
                      | Error e -> failtest (dict + ": " + e.Message)

                  // A stream with no filter is plain bytes: the name scan has them already.
                  let raw =
                      objStmPdf [ "<</Type/ObjStm/N 1/First 4/Length 40>>", inner "<< /Type /Page >>" ]

                  Expect.equal (codeOf (receive config false raw)) "ok" "no filter, clean"

                  let rawBad =
                      objStmPdf [ "<</Type/ObjStm/N 1/First 4/Length 40>>", inner "<< /JS (x) >>" ]

                  Expect.equal (codeOf (receive config false rawBad)) "active_content" "no filter, active")
          }

          test "an object stream that cannot be scanned is refused with pdf_unscannable" {
              withConfig 10_000_000L (fun config ->
                  let body = zlib Compression.CompressionLevel.Optimal (inner "<< /S /JavaScript >>")

                  let hex = Encoding.ASCII.GetBytes(Convert.ToHexString body)

                  let refused (why: string) (dict: string) (data: byte[]) =
                      Expect.equal (codeOf (receive config true (objStmPdf [ dict, data ]))) "pdf_unscannable" why

                  refused "other filter" "<</Type/ObjStm/N 1/First 4/Filter/ASCIIHexDecode/Length 9>>" hex

                  refused
                      "two filters"
                      "<</Type/ObjStm/N 1/First 4/Filter[/FlateDecode/ASCIIHexDecode]/Length 9>>"
                      body

                  refused "two filters, order" "<</Type/ObjStm/Filter[/ASCII85Decode/FlateDecode]/N 1/First 4>>" body

                  refused
                      "a predictor"
                      "<</Type/ObjStm/N 1/First 4/Filter/FlateDecode/DecodeParms<</Predictor 12>>>>"
                      body

                  refused "an unknown key" "<</Type/ObjStm/N 1/First 4/Filter/FlateDecode/Foo 1>>" body
                  refused "escaped filter name" "<</Type/ObjStm/N 1/First 4/Filter/Flate#44ecode>>" body
                  // A `<<` inside a string must not hide the filter array that came before it.
                  refused
                      "a spoofed dictionary start"
                      "<</Filter[/FlateDecode/ASCIIHexDecode]/S(<<)/Type/ObjStm/N 1/First 4>>"
                      body

                  refused
                      "a spoofed dictionary start in a comment"
                      "<</Filter[/FlateDecode/ASCIIHexDecode]%obj <<\n/Type/ObjStm/N 1/First 4>>"
                      body

                  refused
                      "a spoofed header in a comment"
                      "<</Filter[/FlateDecode/ASCIIHexDecode]%1 0 obj <<\n/Type/ObjStm/N 1/First 4>>"
                      body

                  refused "not zlib" flateDict "this is not a zlib stream at all, not even close"B
                  refused "cut short" flateDict body[.. body.Length - 6]
                  Expect.isEmpty (files config) "no file is left")
          }

          test "an encrypted file is refused, also with an escaped name" {
              withConfig 10_000_000L (fun config ->
                  Expect.equal (codeOf (receive config true (pdfBytes "/Encrypt 5 0 R" 0))) "pdf_encrypted" "name"

                  Expect.equal
                      (codeOf (receive config false (pdfBytes "/Enc#72ypt 5 0 R" 0)))
                      "pdf_encrypted"
                      "escaped"

                  Expect.equal (codeOf (receive config false (pdfBytes "/Encrypted 1" 0))) "ok" "a similar name"
                  Expect.isEmpty (files config) "no file is left")
          }

          test "a zip bomb as an object stream is refused fast and with bounded memory" {
              withConfig 100_000_000L (fun config ->
                  // 200 MB of zeros, about 200 KB compressed: over the 32 MB cap of one stream.
                  let bomb = objStmPdf [ flateDict, zlibZeros 200_000_000 ]
                  Expect.isLessThan bomb.Length 2_000_000 "the bomb itself is small"
                  let before = GC.GetAllocatedBytesForCurrentThread()
                  let clock = Diagnostics.Stopwatch.StartNew()
                  Expect.equal (codeOf (receive config true bomb)) "pdf_unscannable" "refused"
                  Expect.isLessThan clock.Elapsed.TotalSeconds 10.0 "fast"

                  Expect.isLessThan
                      (GC.GetAllocatedBytesForCurrentThread() - before)
                      16_000_000L
                      "it does not build the 200 MB"

                  Expect.isEmpty (files config) "no file is left")
          }

          test "the cap of 128 MB for a whole file counts all its streams" {
              withConfig 100_000_000L (fun config ->
                  // Each stream inflates to 30 MB, under the cap of one stream, five of them to 150 MB.
                  let one = zlibZeros 30_000_000
                  let five = objStmPdf (List.replicate 5 (flateDict, one))
                  Expect.equal (codeOf (receive config false five)) "pdf_unscannable" "five"
                  let three = objStmPdf (List.replicate 3 (flateDict, one))
                  Expect.equal (codeOf (receive config false three)) "ok" "three, 90 MB")
          } ]
