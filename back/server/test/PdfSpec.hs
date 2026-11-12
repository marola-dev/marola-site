module PdfSpec (spec, withConfig) where

import Codec.Compression.Zlib qualified as Z
import Control.Exception (ErrorCall, bracket, evaluate, try)
import Control.Monad (forM_)
import Data.Bits ((.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Harness
import Marola.Server.Config (Config (..))
import Marola.Server.PdfIntake (Received (..))
import Marola.Server.PdfIntake qualified as PdfIntake
import Marola.Study (FieldError (..))
import System.Directory (doesDirectoryExist, doesFileExist, removePathForcibly)
import System.FilePath ((</>))
import System.Posix.Files (fileMode, getFileStatus)
import Test.Hspec

withConfig :: Int64 -> (Config -> IO a) -> IO a
withConfig quota body = bracket (tempDir "marola-pdf-") removePathForcibly $ \root ->
  body
    (bareConfig (root </> "db" </> "marola.db"))
      { studies = root </> "studies",
        studiesQuota = quota,
        githubClientId = Just "test-client-id",
        githubBase = "https://github.test",
        githubApiBase = "https://api.github.test"
      }

receive :: Config -> Bool -> ByteString -> IO (Either FieldError Received)
receive = PdfIntake.receiveBytes

codeOf :: Either FieldError Received -> Text
codeOf = either (.code) (const "ok")

code :: Config -> Bool -> ByteString -> IO Text
code c s b = codeOf <$> receive c s b

ok :: Either FieldError Received -> IO Received
ok = either (\e -> expectationFailure (T.unpack e.message) >> error "unreachable") pure

files :: Config -> IO [FilePath]
files c = filesUnder c.studies

zlib :: ByteString -> ByteString
zlib = BL.toStrict . Z.compress . BL.fromStrict

-- | @n@ bytes of zero, compressed from a lazy stream that is never held whole.
zlibZeros :: Int64 -> ByteString
zlibZeros n = BL.toStrict (Z.compressWith Z.defaultCompressParams {Z.compressLevel = Z.bestSpeed} (BL.replicate n 0))

objStmPdf :: [(Text, ByteString)] -> ByteString
objStmPdf streams =
  B.concat $
    [latin1 "%PDF-1.5\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"]
      <> concat [[latin1 (T.pack (show (10 + i :: Int)) <> " 0 obj\n" <> d <> "\nstream\n"), body, latin1 "\nendstream\nendobj\n"] | (i, (d, body)) <- zip [0 ..] streams]
      <> [latin1 "trailer\n<< /Root 1 0 R >>\nstartxref\n9\n%%EOF\n"]

flateDict :: Text
flateDict = "<</Type/ObjStm/N 1/First 4/Filter/FlateDecode/Length 99>>"

inner :: Text -> ByteString
inner t = latin1 ("5 0 " <> t)

spec :: Spec
spec = do
  describe "pdf intake" $ do
    it "a valid file is hashed while it streams, written 0640 to a temp file and moved to <sha256>.pdf" $ withConfig 10_000_000 $ \config -> do
      let bytes = pdfBytes "" 200000
      r <- ok =<< receive config True bytes
      r.sha256 `shouldBe` sha bytes
      r.size `shouldBe` fromIntegral (B.length bytes)
      let Just temp = r.temp
      doesFileExist temp `shouldReturn` True
      mode <- fileMode <$> getFileStatus temp
      (mode .&. 0o027) `shouldBe` 0
      (mode .&. 0o400) `shouldBe` 0o400
      PdfIntake.commit config r
      let final = PdfIntake.pathOf config r.sha256
      doesFileExist final `shouldReturn` True
      doesFileExist temp `shouldReturn` False
      B.readFile final `shouldReturn` bytes
      PdfIntake.commit config =<< ok =<< receive config True bytes
      length <$> files config `shouldReturn` 1

    it "a dry run creates no file and no folder" $ withConfig 10_000_000 $ \config -> do
      r <- ok =<< receive config False validPdf
      r.temp `shouldBe` Nothing
      r.sha256 `shouldBe` sha validPdf
      doesDirectoryExist config.studies `shouldReturn` False

    it "bad magic, empty and truncated files are refused and leave nothing" $ withConfig 10_000_000 $ \config -> do
      code config True "PK\3\4 not a pdf" `shouldReturn` "not_pdf"
      code config True "" `shouldReturn` "not_pdf"
      code config True " %PDF-1.4" `shouldReturn` "not_pdf"
      code config True (B.take (B.length validPdf - 19) validPdf) `shouldReturn` "truncated"
      code config True "%PDF-1.4\n1 0 obj\n<< >>\n" `shouldReturn` "truncated"
      files config `shouldReturn` []

    it "active content is refused: names, escaped names, and an OpenAction with an action" $ withConfig 10_000_000 $ \config -> do
      forM_
        [ "/AA << /O << /S /JavaScript /JS (app.alert(1)) >> >>",
          "/JS (app.alert(1))",
          "/JS(app.alert(1))",
          "/S /Launch /F (cmd.exe)",
          "/Names << /EmbeddedFiles << >> >> /Type /EmbeddedFile",
          "/OpenAction << /S /URI /URI (https://evil.example) >>",
          "/OpenAction<</S/GoTo>>",
          "/OpenAction /Foo",
          "/J#53 (x)",
          "/#4AavaScript",
          "/#4a#61vaScript"
        ]
        $ \extra -> (extra,) <$> code config True (pdfBytes extra 0) `shouldReturn` (extra, "active_content")
      files config `shouldReturn` []

    it "plain PDFs with a destination OpenAction, a reference or a similar name are accepted" $ withConfig 10_000_000 $ \config ->
      forM_ ["/OpenAction [3 0 R /Fit]", "/OpenAction 5 0 R", "/OpenAction null", "/OpenAction\n[3 0 R /XYZ 0 0 0]", "/JSON 1 /JavaScripts 2 /Font /Arial#20Bold"] $ \extra ->
        (extra,) <$> code config False (pdfBytes extra 0) `shouldReturn` (extra, "ok")

    it "a forbidden name that straddles the 64 KB read border is found" $ withConfig 10_000_000 $ \config -> do
      let bytes = pdfBytes "/S /JavaScript" 0
          at = B.length (fst (B.breakSubstring "/JavaScript" bytes))
      forM_ [-3 .. 3] $ \shift -> do
        let moved = pdfBytes "/S /JavaScript" (65536 - at + shift - 3)
        (shift,) <$> code config False moved `shouldReturn` (shift, "active_content")

    it "a file over 20 MB is refused while streaming, without reading it all and without a file" $ withConfig 100_000_000 $ \config -> do
      position <- newIORef (0 :: Int64)
      let chunk = B.replicate 65536 0
          next = do
            p <- readIORef position
            if p >= 1_000_000_000 then pure "" else writeIORef position (p + 65536) >> pure chunk
      r <- PdfIntake.receive config True next
      codeOf r `shouldBe` "too_large"
      readIORef position >>= (`shouldSatisfy` (< PdfIntake.maxBytes + 200000))
      files config `shouldReturn` []

    it "a file of exactly 20 MB is not too large" $ withConfig 100_000_000 $ \config -> do
      let bytes = pdfBytes "" (fromIntegral PdfIntake.maxBytes - B.length validPdf - 2)
      fromIntegral (B.length bytes) `shouldBe` PdfIntake.maxBytes
      code config False bytes `shouldReturn` "ok"

    it "the quota counts the stored bytes; a file already stored costs nothing" $ withConfig (fromIntegral (B.length validPdf) + 100) $ \config -> do
      first <- ok =<< receive config True validPdf
      PdfIntake.fitsQuota config first `shouldReturn` True
      PdfIntake.commit config first
      PdfIntake.used config `shouldReturn` fromIntegral (B.length validPdf)
      other <- ok =<< receive config False (pdfBytes "/Foo 1" 0)
      PdfIntake.fitsQuota config other `shouldReturn` False
      again <- ok =<< receive config False validPdf
      PdfIntake.fitsQuota config again `shouldReturn` True

    it "the stored path is built from a hash and refuses anything else" $ withConfig 1 $ \config -> do
      forM_ ["../../etc/passwd", T.replicate 63 "a", T.replicate 64 "A"] $ \bad ->
        (try (evaluate (length (PdfIntake.pathOf config bad))) :: IO (Either ErrorCall Int)) >>= (`shouldSatisfy` either (const True) (const False))
      PdfIntake.pathOf config (T.replicate 64 "a") `shouldBe` config.studies </> (replicate 64 'a' <> ".pdf")

  describe "pdf object streams" $ do
    it "an action inside a compressed object stream is refused, as in a plain one" $ withConfig 10_000_000 $ \config -> do
      let pdf = objStmPdf [(flateDict, zlib (inner "<< /S /JavaScript /JS (app.alert(1)) >>"))]
      code config True pdf `shouldReturn` "active_content"
      code config False pdf `shouldReturn` "active_content"
      let escaped = objStmPdf [(flateDict, zlib (inner "<< /S /Launch /F (cmd.exe) >>")), (flateDict, zlib (inner "<< /J#53 (x) >>"))]
      code config True escaped `shouldReturn` "active_content"
      files config `shouldReturn` []

    it "a clean object stream is accepted, in the forms that Word, LaTeX and qpdf write" $ withConfig 10_000_000 $ \config -> do
      let clean = zlib (inner "<< /Type /Page /Parent 2 0 R /Contents 7 0 R /OpenAction [3 0 R /Fit] >>")
      forM_
        [ flateDict,
          "<</Type/ObjStm/N 69/First 513/Filter/FlateDecode/Length 1531>>",
          "<<\n/Type /ObjStm\n/N 2\n/First 10\n/Length 12 0 R\n/Filter /FlateDecode\n>>",
          "<</Length 99/Filter/FlateDecode/Extends 3 0 R/First 4/N 1/Type/ObjStm>>",
          "<<\r\n/Type /ObjStm /N 1 /First 4 /Filter /FlateDecode /Length 99 \r\n>>"
        ]
        $ \d -> do
          let pdf = objStmPdf [(d, clean)]
          (d,) <$> code config False pdf `shouldReturn` (d, "ok")
          r <- ok =<< receive config True pdf
          PdfIntake.commit config r
          B.readFile (PdfIntake.pathOf config r.sha256) `shouldReturn` pdf
      code config False (objStmPdf [("<</Type/ObjStm/N 1/First 4/Length 40>>", inner "<< /Type /Page >>")]) `shouldReturn` "ok"
      code config False (objStmPdf [("<</Type/ObjStm/N 1/First 4/Length 40>>", inner "<< /JS (x) >>")]) `shouldReturn` "active_content"

    it "an object stream that cannot be scanned is refused with pdf_unscannable" $ withConfig 10_000_000 $ \config -> do
      let body = zlib (inner "<< /S /JavaScript >>")
          hex = BC.pack (concatMap (\w -> let s = "0123456789ABCDEF" in [s !! fromIntegral (w `div` 16), s !! fromIntegral (w `mod` 16)]) (B.unpack body))
          refused why d dat = (why :: Text,) <$> code config True (objStmPdf [(d, dat)]) `shouldReturn` (why, "pdf_unscannable")
      refused "other filter" "<</Type/ObjStm/N 1/First 4/Filter/ASCIIHexDecode/Length 9>>" hex
      refused "two filters" "<</Type/ObjStm/N 1/First 4/Filter[/FlateDecode/ASCIIHexDecode]/Length 9>>" body
      refused "two filters, order" "<</Type/ObjStm/Filter[/ASCII85Decode/FlateDecode]/N 1/First 4>>" body
      refused "a predictor" "<</Type/ObjStm/N 1/First 4/Filter/FlateDecode/DecodeParms<</Predictor 12>>>>" body
      refused "an unknown key" "<</Type/ObjStm/N 1/First 4/Filter/FlateDecode/Foo 1>>" body
      refused "escaped filter name" "<</Type/ObjStm/N 1/First 4/Filter/Flate#44ecode>>" body
      refused "a spoofed dictionary start" "<</Filter[/FlateDecode/ASCIIHexDecode]/S(<<)/Type/ObjStm/N 1/First 4>>" body
      refused "a spoofed dictionary start in a comment" "<</Filter[/FlateDecode/ASCIIHexDecode]%obj <<\n/Type/ObjStm/N 1/First 4>>" body
      refused "a spoofed header in a comment" "<</Filter[/FlateDecode/ASCIIHexDecode]%1 0 obj <<\n/Type/ObjStm/N 1/First 4>>" body
      refused "not zlib" flateDict "this is not a zlib stream at all, not even close"
      refused "cut short" flateDict (B.take (B.length body - 5) body)
      files config `shouldReturn` []

    it "an encrypted file is refused, also with an escaped name" $ withConfig 10_000_000 $ \config -> do
      code config True (pdfBytes "/Encrypt 5 0 R" 0) `shouldReturn` "pdf_encrypted"
      code config False (pdfBytes "/Enc#72ypt 5 0 R" 0) `shouldReturn` "pdf_encrypted"
      code config False (pdfBytes "/Encrypted 1" 0) `shouldReturn` "ok"
      files config `shouldReturn` []

    it "a zip bomb as an object stream is refused fast" $ withConfig 100_000_000 $ \config -> do
      let bomb = objStmPdf [(flateDict, zlibZeros 200_000_000)]
      B.length bomb `shouldSatisfy` (< 2_000_000)
      t0 <- getCurrentTime
      code config True bomb `shouldReturn` "pdf_unscannable"
      t1 <- getCurrentTime
      diffUTCTime t1 t0 `shouldSatisfy` (< 10)
      files config `shouldReturn` []

    it "the cap of 128 MB for a whole file counts all its streams" $ withConfig 100_000_000 $ \config -> do
      let one = zlibZeros 30_000_000
      code config False (objStmPdf (replicate 5 (flateDict, one))) `shouldReturn` "pdf_unscannable"
      code config False (objStmPdf (replicate 3 (flateDict, one))) `shouldReturn` "ok"
