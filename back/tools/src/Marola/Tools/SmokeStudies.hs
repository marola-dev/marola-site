-- | The study API on the built server: no key is a 401, a dry run stores nothing, a real submission is
-- read back and its hash is the one `sha256sum` printed.
module Marola.Tools.SmokeStudies (main) where

import Codec.Compression.Zlib qualified as Z
import Control.Monad (filterM, unless)
import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as V
import Marola.Tools.Client
import Network.HTTP.Client qualified as H
import Network.HTTP.Client.MultipartFormData (Part, PartM (..), partBS, partFileRequestBody)
import Numeric (showFFloat)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Exit (exitFailure)
import System.FilePath ((</>))

-- | The fields of a submission. `small` sends a stub file: a refusal that comes before the body is read
-- (401, 429) would break a 2 MB upload mid-write, and that is the client's problem, not this check's.
form :: ByteString -> [Part]
form pdf =
  [ partBS "title" "Smoke test of the study API",
    partBS "authors" "Ana Silva | 0000-0002-1825-0097",
    partBS "abstract" (B.concat (replicate 10 "A smoke test study. ")),
    partBS "area" "rio",
    partBS "topic" "data",
    partBS "rights" "true",
    partBS "ai_contribution" "none",
    pdfPart "smoke.pdf" pdf
  ]

pdfPart :: Text -> ByteString -> Part
pdfPart name bytes =
  (partFileRequestBody "pdf" (T.unpack name) (H.RequestBodyBS bytes))
    { partContentType = Just "application/pdf"
    }

withPdf :: Text -> ByteString -> [Part] -> [Part]
withPdf name bytes parts = init parts <> [pdfPart name bytes]

pdfWith :: ByteString -> ByteString -> ByteString
pdfWith extraTrailer objects =
  "%PDF-1.5\n1 0 obj\n<< /Type /Catalog >>\nendobj\n" <> objects <> "trailer\n<< /Root 1 0 R " <> extraTrailer <> " >>\nstartxref\n9\n%%EOF\n"

objStm :: ByteString -> ByteString
objStm inner =
  "10 0 obj\n<</Type/ObjStm/N 1/First 4/Filter/FlateDecode/Length 99>>\nstream\n"
    <> BL.toStrict (Z.compress (BL.fromStrict ("5 0 " <> inner)))
    <> "\nendstream\nendobj\n"

main :: [String] -> IO ()
main = \case
  [base, key, pdfPath, expectedSha, studiesDir] -> run base (BC.pack key) pdfPath (T.pack expectedSha) studiesDir
  _ -> fail "usage: marola-tools smoke-studies <base> <key> <pdf> <sha256> <studies-dir>"

run :: String -> ByteString -> FilePath -> Text -> FilePath -> IO ()
run base key pdfPath expectedSha studiesDir = do
  m <- newManager
  c <- newChecks ""
  pdf <- B.readFile pdfPath
  let check cond what = ok c cond what ""
      auth = [("Authorization", "Bearer " <> key)]
      small = withPdf "smoke.pdf" "x" (form pdf)
      files = do
        exists <- doesDirectoryExist studiesDir
        if not exists
          then pure []
          else sort <$> (filterM (doesFileExist . (studiesDir </>)) . filter (".pdf" `isSuffixOf`) =<< listDirectory studiesDir)
      jstr k v = str (field k v)
      studies v = case field "studies" v of
        A.Array xs -> V.toList xs
        _ -> []

  none <- postMultipart m base "/api/v1/studies" [] small
  check (none.status == 401) "a POST without a key is a 401"

  dry <- postMultipart m base "/api/v1/studies?dry_run=1" auth (form pdf)
  let dryBody = json dry
  check (dry.status == 200 && field "dry_run" dryBody == A.Bool True) "a dry run answers 200"
  check (jstr "sha256" dryBody == Just expectedSha) "the dry run hash equals sha256sum"
  noFiles <- files
  check (null noFiles) "a dry run leaves no file"
  emptyList <- json <$> get m base "/api/v1/studies"
  check (null (studies emptyList)) "a dry run leaves no row"

  -- The scan reaches inside object streams and refuses a file it cannot read (ADR 0004): all as dry runs.
  let dryCode bytes = do
        r <- postMultipart m base "/api/v1/studies?dry_run=1" auth (withPdf "x.pdf" bytes small)
        let j = json r
            code = case field "errors" j of
              A.Array xs | Just e <- xs V.!? 0, Just s <- jstr "code" e -> s
              _ -> if field "dry_run" j == A.Bool True then "ok" else "?"
        pure (r.status, code)
  r1 <- dryCode (pdfWith "/Encrypt 7 0 R" "")
  check (r1 == (400, "pdf_encrypted")) "an encrypted PDF is refused (pdf_encrypted)"
  r2 <- dryCode (pdfWith "" (objStm "<< /S /JavaScript /JS (x) >>"))
  check (r2 == (400, "active_content")) "an action inside an object stream is refused"
  r3 <- dryCode (pdfWith "" (objStm "<< /Type /Page >>"))
  check (r3 == (200, "ok")) "a clean object stream is accepted"
  r4 <- dryCode (pdfWith "" "10 0 obj\n<</Type/ObjStm/N 1/First 4/Filter/ASCIIHexDecode/Length 9>>\nstream\n35203020\nendstream\nendobj\n")
  check (r4 == (400, "pdf_unscannable")) "an object stream with another filter is refused (pdf_unscannable)"
  leftover <- files
  check (null leftover) "the refused and dry-run files leave nothing"

  real <- postMultipart m base "/api/v1/studies" auth (form pdf)
  let receipt = json real
      mb = T.pack (showFFloat (Just 1) (fromIntegral (B.length pdf) / 1e6 :: Double) "")
  check (real.status == 201) ("a real submission answers 201 (" <> T.pack (show real.status) <> ", a " <> mb <> " MB file)")
  check (jstr "sha256" receipt == Just expectedSha) "the receipt hash equals sha256sum"
  stored <- files
  check (stored == [T.unpack expectedSha <> ".pdf"]) "the file is stored as <sha256>.pdf"

  let rid = maybe "" id (jstr "id" receipt)
  record <- json <$> get m base (TE.encodeUtf8 ("/api/v1/studies/" <> rid))
  check (jstr "id" record == Just rid && jstr "review" record == Just "not reviewed") "the record reads back, labelled not reviewed"

  file <- get m base (TE.encodeUtf8 (maybe "" id (jstr "pdf_url" receipt)))
  check (file.status == 200 && BL.toStrict file.body == pdf) "the PDF reads back byte for byte"
  check (hdr "content-type" file == Just "application/pdf") "the PDF is application/pdf"
  check (hdr "content-security-policy" file == Just "sandbox; default-src 'none'") "the PDF has the sandbox CSP"
  check (hdr "x-content-type-options" file == Just "nosniff") "the PDF has nosniff"

  again <- postMultipart m base "/api/v1/studies" auth small
  check (again.status == 429) "a second submission at once is a 429"

  skill <- get m base "/api/v1/skill.md"
  check (skill.status == 200 && "dry_run=1" `T.isInfixOf` text skill) "skill.md is served"

  openapi <- get m base "/api/v1/openapi.json"
  let doc = json openapi
      hasPost = case field "/api/v1/studies" (field "paths" doc) of
        A.Object o -> KM.member "post" o
        _ -> False
  check
    ( openapi.status == 200
        && hdr "content-type" openapi == Just "application/json; charset=utf-8"
        && hdr "cache-control" openapi == Just "public, max-age=300"
        && jstr "openapi" doc == Just "3.1.0"
        && hasPost
    )
    "openapi.json is served as OpenAPI 3.1 with its cache header"

  n <- failures c
  unless (n == 0) exitFailure
