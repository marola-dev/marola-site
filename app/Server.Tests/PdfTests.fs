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
          StudiesQuota = quota }

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
