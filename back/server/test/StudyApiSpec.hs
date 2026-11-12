module StudyApiSpec (spec, goodFields, newAccount, sendBody) where

import Control.Monad (forM, forM_)
import Data.Aeson qualified as A
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Foldable (toList)
import Data.IORef
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (addUTCTime)
import Harness
import Marola.Server.Config (Config (..))
import Marola.Server.Store (utc)
import Marola.Server.StudyStore (Account (..), KeyInfo (..))
import Marola.Server.StudyStore qualified as StudyStore
import Marola.Study (Record (..))
import Network.HTTP.Types (Header, hAuthorization, hContentType)
import System.Directory (doesDirectoryExist)
import System.FilePath ((</>))
import Test.Hspec

goodFields :: [(ByteString, Text)]
goodFields =
  [ ("title", "Enterococcus in Praia do Leblon, 2025"),
    ("authors", "Ana Silva | 0000-0002-1825-0097\nBruno Costa"),
    ("abstract", T.replicate 12 "Sampling of bathing water. "),
    ("area", "rio"),
    ("topic", "water-quality"),
    ("sources", "https://example.org/data"),
    ("rights", "true"),
    ("ai_contribution", "none")
  ]

-- | An account of that age with a key.
newAccount :: Site -> Int64 -> Text -> Integer -> IO Text
newAccount site i l ageDays = do
  now <- readIORef site.clock
  StudyStore.upsertAccount site.config.db now Account {githubId = i, login = l, createdGithubUtc = utc (addUTCTime (fromInteger (negate ageDays) * 86400) now)}
  either (error . show) id <$> StudyStore.issueKey site.config.db now i

sendBody :: Site -> Maybe Text -> ByteString -> ([Header], BL.ByteString) -> IO Res
sendBody site key url (hs, b) = send site (post url (hs <> maybe [] (\k -> [(hAuthorization, "Bearer " <> TE.encodeUtf8 k)]) key) b)

submit :: Site -> Text -> [(ByteString, Text)] -> ByteString -> IO Res
submit site key fields pdf = sendBody site (Just key) "/api/v1/studies" (studyBody fields (Just pdf))

dryRun :: Site -> Text -> ([Header], BL.ByteString) -> IO Res
dryRun site key = sendBody site (Just key) "/api/v1/studies?dry_run=1"

rows :: Site -> IO [Text]
rows site = map (.id) <$> StudyStore.listStudies site.config.db Nothing Nothing Nothing 50

later :: Site -> IO ()
later site = advance site 660

ids :: Res -> [Text]
ids res = case jpath ["studies"] (jsonOf res) of
  A.Array xs -> [jtext ["id"] x | x <- toList xs]
  _ -> []

spec :: Spec
spec = describe "study api" $ do
  it "a submission is stored and answered with 201, the id, the links, the hash and the record" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    r <- submit site key goodFields validPdf
    (r.status, bodyText r) `shouldSatisfy` ((== 201) . fst)
    header r "Content-Type" `shouldBe` Just "application/json; charset=utf-8"
    header r "X-Content-Type-Options" `shouldBe` Just "nosniff"
    let j = jsonOf r
        i = jtext ["id"] j
    jtext ["sha256"] j `shouldBe` sha validPdf
    jtext ["received_utc"] j `shouldBe` "2026-11-11T12:00:00Z"
    jtext ["status"] j `shouldBe` "public"
    jtext ["url"] j `shouldBe` "/studies/" <> i
    jtext ["pdf_url"] j `shouldBe` "/studies/" <> i <> ".pdf"
    jtext ["record", "review"] j `shouldBe` "not reviewed"
    jtext ["record", "author_login"] j `shouldBe` "ana"
    BS.readFile (site.config.studies </> T.unpack (sha validPdf) <> ".pdf") >>= (`shouldBe` validPdf)
    length <$> rows site >>= (`shouldBe` 1)

  it "the PDF route serves the file with the sandbox headers that replace the page CSP" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    created <- submit site key goodFields validPdf
    let i = TE.encodeUtf8 (jtext ["id"] (jsonOf created))
    r <- send site (get ("/studies/" <> i <> ".pdf"))
    r.status `shouldBe` 200
    header r "Content-Type" `shouldBe` Just "application/pdf"
    header r "Content-Disposition" `shouldBe` Just ("inline; filename=\"" <> i <> ".pdf\"")
    header r "X-Content-Type-Options" `shouldBe` Just "nosniff"
    header r "Content-Security-Policy" `shouldBe` Just "sandbox; default-src 'none'"
    header r "Cache-Control" `shouldBe` Just "public, max-age=3600"
    BL.toStrict r.body `shouldBe` validPdf

  it "a dry run answers what it would do and leaves no file, no folder and no row" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    r <- dryRun site key (studyBody goodFields (Just validPdf))
    r.status `shouldBe` 200
    jpath ["dry_run"] (jsonOf r) `shouldBe` A.Bool True
    jtext ["sha256"] (jsonOf r) `shouldBe` sha validPdf
    rows site >>= (`shouldBe` [])
    doesDirectoryExist site.config.studies >>= (`shouldBe` False)
    real <- submit site key goodFields validPdf
    real.status `shouldBe` 201

  it "a dry run finds the same errors, the duplicate and the 10 minute gap" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    first <- submit site key goodFields validPdf
    first.status `shouldBe` 201
    soon <- dryRun site key (studyBody goodFields (Just (pdfBytes "/A 1" 0)))
    soon.status `shouldBe` 429
    later site
    dup <- dryRun site key (studyBody goodFields (Just validPdf))
    dup.status `shouldBe` 409
    bad <- dryRun site key (studyBody (drop 1 goodFields) (Just validPdf))
    bad.status `shouldBe` 400
    length <$> rows site >>= (`shouldBe` 1)
    length <$> filesUnder site.config.studies >>= (`shouldBe` 1)

  it "401 without a key, with a wrong key and with a revoked key; 403 for a young account" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    none <- sendBody site Nothing "/api/v1/studies" (studyBody goodFields (Just validPdf))
    none.status `shouldBe` 401
    errorCodes none `shouldBe` [("request", "unauthorized")]
    header none "WWW-Authenticate" `shouldBe` Just "Bearer"
    wrong <- submit site (T.take 55 key <> (if T.isSuffixOf "a" key then "b" else "a")) goodFields validPdf
    wrong.status `shouldBe` 401
    junk <- submit site "msk_../../etc" goodFields validPdf
    junk.status `shouldBe` 401
    k : _ <- StudyStore.listKeys site.config.db 1
    now <- readIORef site.clock
    _ <- StudyStore.revokeKey site.config.db now 1 k.id
    revoked <- submit site key goodFields validPdf
    revoked.status `shouldBe` 401
    young <- newAccount site 2 "novo" 6
    r <- submit site young goodFields validPdf
    r.status `shouldBe` 403
    errorCodes r `shouldBe` [("request", "account_too_new")]
    rows site >>= (`shouldBe` [])

  it "400 lists every error at once with codes, and a bad file adds its own" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    r <- submit site key [("title", "no"), ("authors", "Ana | 0000-0002-1825-0098"), ("area", "mars"), ("rights", "false"), ("ai_contribution", "drafting")] "not a pdf"
    r.status `shouldBe` 400
    forM_ [("title", "too_short"), ("authors", "bad_orcid"), ("abstract", "required"), ("area", "unknown_value"), ("topic", "required"), ("rights", "must_be_true"), ("ai_process", "required"), ("pdf", "not_pdf")] $ \e ->
      errorCodes r `shouldContain` [e]
    missing <- sendBody site (Just key) "/api/v1/studies" (studyBody goodFields Nothing)
    errorCodes missing `shouldBe` [("pdf", "required")]
    js <- submit site key goodFields (pdfBytes "/S /JavaScript" 0)
    errorCodes js `shouldBe` [("pdf", "active_content")]
    cut <- submit site key goodFields (BS.take (BS.length validPdf - 24) validPdf)
    errorCodes cut `shouldBe` [("pdf", "truncated")]
    filesUnder site.config.studies >>= (`shouldBe` [])

  it "the same file from the same account is a 409 that names the old id; another account may send it" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    other <- newAccount site 2 "bia" 30
    first <- submit site key goodFields validPdf
    let i = jtext ["id"] (jsonOf first)
    later site
    dup <- submit site key goodFields validPdf
    dup.status `shouldBe` 409
    jtext ["id"] (jsonOf dup) `shouldBe` i
    theirs <- submit site other goodFields validPdf
    theirs.status `shouldBe` 201
    length <$> filesUnder site.config.studies >>= (`shouldBe` 1)

  it "413 for a file over 20 MB (by the stream) and for a request over 21 MB (by its length)" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    big <- submit site key goodFields (BS.replicate (20 * 1024 * 1024 + 1) 0)
    big.status `shouldBe` 413
    errorCodes big `shouldBe` [("pdf", "too_large")]
    huge <- submit site key goodFields (BS.replicate (22 * 1024 * 1024) 0)
    huge.status `shouldBe` 413
    filesUnder site.config.studies >>= (`shouldBe` [])

  it "415 for a JSON body and a form body" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    j <- sendBody site (Just key) "/api/v1/studies" ([(hContentType, "application/json; charset=utf-8")], "{}")
    j.status `shouldBe` 415
    f <- sendBody site (Just key) "/api/v1/studies" ([(hContentType, "application/x-www-form-urlencoded")], formBody [(k, TE.encodeUtf8 v) | (k, v) <- goodFields])
    f.status `shouldBe` 415

  it "429: one real submission every 10 minutes, and the 11th in a day" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    first <- submit site key goodFields (pdfBytes "/N 0" 0)
    first.status `shouldBe` 201
    soon <- submit site key goodFields (pdfBytes "/N 1" 0)
    soon.status `shouldBe` 429
    errorCodes soon `shouldBe` [("request", "too_soon")]
    header soon "Retry-After" `shouldBe` Just "600"
    forM_ [2 .. 10 :: Int] $ \i -> do
      later site
      r <- submit site key goodFields (pdfBytes ("/N " <> T.pack (show i)) 0)
      (i, r.status) `shouldBe` (i, 201)
    later site
    eleventh <- submit site key goodFields (pdfBytes "/N 11" 0)
    eleventh.status `shouldBe` 429
    errorCodes eleventh `shouldBe` [("request", "daily_limit")]
    length <$> rows site >>= (`shouldBe` 10)
    advance site 86400
    next <- submit site key goodFields (pdfBytes "/N 12" 0)
    next.status `shouldBe` 201

  it "30 requests a minute per key: dry runs count a third, so 90 pass and the 91st is a 429" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    codes <- forM [1 .. 90 :: Int] $ \_ -> (.status) <$> dryRun site key (studyBody [] Nothing)
    codes `shouldBe` replicate 90 400
    over <- dryRun site key (studyBody [] Nothing)
    over.status `shouldBe` 429
    errorCodes over `shouldBe` [("request", "rate_limited")]
    advance site 61
    again <- dryRun site key (studyBody [] Nothing)
    again.status `shouldBe` 400

  it "507 when the store is full: the quota refuses a new file and a dry run says so" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    let big = pdfBytes "" 1100000
    d <- dryRun site key (studyBody goodFields (Just big))
    d.status `shouldBe` 507
    r <- submit site key goodFields big
    r.status `shouldBe` 507
    errorCodes r `shouldBe` [("pdf", "quota_exceeded")]
    filesUnder site.config.studies >>= (`shouldBe` [])
    rows site >>= (`shouldBe` [])

  it "multipart limits: duplicate names, non-UTF-8, unknown fields, too many parts, oversized fields" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    dup <- dryRun site key (studyBody (goodFields <> [("title", "again")]) (Just validPdf))
    errorCodes dup `shouldContain` [("request", "duplicate_field")]
    let noTitle = [f | f@(k, _) <- goodFields, k /= "title"]
        pdfPart = Part "pdf" (BL.fromStrict validPdf) (Just "study.pdf")
    utf <- dryRun site key (multipart ([field k v | (k, v) <- noTitle] <> [pdfPart, Part "title" (BL.pack [0xff, 0xfe, 0x41]) Nothing]))
    errorCodes utf `shouldContain` [("title", "invalid_utf8")]
    unknown <- dryRun site key (studyBody (goodFields <> [("evil", "x")]) (Just validPdf))
    errorCodes unknown `shouldContain` [("request", "unknown_field")]
    parts <- dryRun site key (studyBody [(TE.encodeUtf8 ("f" <> T.pack (show i)), "x") | i <- [1 .. 25 :: Int]] (Just validPdf))
    errorCodes parts `shouldContain` [("request", "too_many_parts")]
    long <- dryRun site key (studyBody [(k, if k == "title" then T.replicate 21000 "a" else v) | (k, v) <- goodFields] (Just validPdf))
    errorCodes long `shouldContain` [("title", "too_long")]
    noBoundary <- sendBody site (Just key) "/api/v1/studies" ([(hContentType, "multipart/form-data")], "x")
    noBoundary.status `shouldBe` 400

  it "control characters are stripped from stored text" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    r <- submit site key [(k, if k == "title" then "Water\SOH at\ESC Leblon" else v) | (k, v) <- goodFields] validPdf
    r.status `shouldBe` 201
    jtext ["record", "title"] (jsonOf r) `shouldBe` "Water at Leblon"

  it "GET: the record, the list with filters and paging, 404 for bad and unknown ids" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    made <- forM [0 .. 2 :: Int] $ \i -> do
      r <- submit site key [(k, if k == "area" && i == 1 then "floripa" else v) | (k, v) <- goodFields] (pdfBytes ("/N " <> T.pack (show i)) 0)
      later site
      pure (jtext ["id"] (jsonOf r))
    let [a, b, c] = made
        u = TE.encodeUtf8
    one <- send site (get ("/api/v1/studies/" <> u a))
    one.status `shouldBe` 200
    header one "Content-Type" `shouldBe` Just "application/json; charset=utf-8"
    jtext ["id"] (jsonOf one) `shouldBe` a
    ids <$> send site (get "/api/v1/studies") >>= (`shouldBe` [c, b, a])
    ids <$> send site (get "/api/v1/studies?area=rio") >>= (`shouldBe` [c, a])
    page <- send site (get ("/api/v1/studies?limit=1&before=" <> u c))
    ids page `shouldBe` [b]
    jtext ["next_before"] (jsonOf page) `shouldBe` b
    (.status) <$> send site (get "/api/v1/studies?limit=51") >>= (`shouldBe` 400)
    length . errorCodes <$> send site (get "/api/v1/studies?area=mars&before=x") >>= (`shouldBe` 2)
    forM_ ["/api/v1/studies/aaaaaaaaaa", "/api/v1/studies/..%2f..%2fsecret", "/studies/..%2f..%2fsecret.pdf", "/studies/aaaaaaaaaa.pdf"] $ \p ->
      (,) p . (.status) <$> send site (get p) >>= (`shouldBe` (p, 404))

  it "a hidden study is a tombstone: no text, no file link, no file, and it leaves the list" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    created <- submit site key goodFields validPdf
    let i = jtext ["id"] (jsonOf created)
    now <- readIORef site.clock
    StudyStore.hide site.config.db now i "wrong unit" >>= (`shouldBe` True)
    one <- send site (get ("/api/v1/studies/" <> TE.encodeUtf8 i))
    one.status `shouldBe` 200
    let t = bodyText one
    forM_ ["\"status\":\"hidden\"", "wrong unit", sha validPdf, "2026-11-11T12:00:00Z"] $ \n -> t `shouldSatisfy` T.isInfixOf n
    forM_ ["Enterococcus", "pdf_url"] $ \n -> t `shouldNotSatisfy` T.isInfixOf n
    file <- send site (get ("/studies/" <> TE.encodeUtf8 i <> ".pdf"))
    file.status `shouldBe` 404
    bodyText file `shouldNotSatisfy` T.isInfixOf "%PDF"
    ids <$> send site (get "/api/v1/studies") >>= (`shouldBe` [])

  it "skill.md is plain text, names the endpoint, the dry run, the levels and holds no key" $ withSite $ \site -> do
    r <- send site (get "/api/v1/skill.md")
    r.status `shouldBe` 200
    header r "Content-Type" `shouldBe` Just "text/plain; charset=utf-8"
    forM_ ["/api/v1/studies", "dry_run=1", "curl", "autonomous", "language-editing", "%PDF-", "%%EOF", "429", "507"] $ \n ->
      bodyText r `shouldSatisfy` T.isInfixOf n
    bodyText r `shouldNotSatisfy` T.isInfixOf "msk_a"

  it "the log has the study id and the account id, and nothing the author wrote" $ withSite $ \site -> do
    key <- newAccount site 1 "ana" 30
    r <- submit site key goodFields validPdf
    let i = jtext ["id"] (jsonOf r)
    l <- T.unlines <$> logLines site
    l `shouldSatisfy` T.isInfixOf i
    forM_ ["Enterococcus", "Sampling", "study.pdf", "Ana Silva", key, "127.0.0.1"] $ \s -> (s, s `T.isInfixOf` l) `shouldBe` (s, False)
