module WebSpec (spec) where

import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAsciiLower)
import Data.IORef
import Data.Int (Int64)
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (addUTCTime)
import Harness
import Marola.Server.Config (Config (..))
import Marola.Server.Http (Env (..))
import Marola.Server.Messages qualified as Messages
import Marola.Server.Session qualified as Session
import Marola.Server.Store (utc)
import Marola.Server.StudyApi qualified as StudyApi
import Marola.Server.StudyStore (Account (..), KeyInfo (..))
import Marola.Server.StudyStore qualified as StudyStore
import Marola.Study
import Network.HTTP.Types (Header, hContentType)
import StudyApiSpec (goodFields)
import Test.Hspec

same :: ByteString
same = "http://localhost"

-- | An account of 30 days at GitHub with a live session: the cookie a browser would hold and its CSRF token.
loggedIn :: Site -> Int64 -> Text -> IO (ByteString, Text)
loggedIn site i l = do
  now <- readIORef site.clock
  StudyStore.upsertAccount site.config.db now Account {githubId = i, login = l, createdGithubUtc = utc (addUTCTime (-30 * 86400) now)}
  tok <- StudyStore.createSession site.config.db now i
  Just (_, h) <- StudyStore.getSession site.config.db now tok
  pure ("__Host-msess=" <> TE.encodeUtf8 tok, Session.csrfToken site.env.csrfKey h)

request :: ByteString -> ByteString -> Maybe ByteString -> Maybe ByteString -> ([Header], BL.ByteString) -> Req
request m url c origin (hs, b) =
  (post url (hs <> maybe [] (\v -> [("Cookie", v)]) c <> maybe [] (\o -> [("Origin", o)]) origin) b) {method = m}

page :: Site -> ByteString -> Maybe ByteString -> IO Res
page site url c = send site (get url) {headers = maybe [] (\v -> [("Cookie", v)]) c}

form :: [(ByteString, Text)] -> ([Header], BL.ByteString)
form pairs = ([(hContentType, "application/x-www-form-urlencoded")], formBody [(k, TE.encodeUtf8 v) | (k, v) <- pairs])

studyForm :: Maybe Text -> [(ByteString, Text)] -> Maybe ByteString -> ([Header], BL.ByteString)
studyForm csrf fields = studyBody (maybe [] (\c -> [("csrf", c)]) csrf <> fields)

postSubmit :: Site -> ByteString -> ByteString -> Maybe ByteString -> ([Header], BL.ByteString) -> IO Res
postSubmit site url c origin b = send site (request "POST" url (Just c) origin b)

idFrom :: Res -> Text
idFrom r = T.takeWhileEnd (/= '/') (maybe "" TE.decodeUtf8 (header r "Location"))

-- | Publishes one study through the form and returns its id.
publish :: Site -> ByteString -> Text -> [(ByteString, Text)] -> ByteString -> IO Text
publish site c csrf fields pdf = do
  r <- postSubmit site "/submit" c (Just same) (studyForm (Just csrf) fields (Just pdf))
  (r.status, bodyText r) `shouldSatisfy` ((== 303) . fst)
  pure (idFrom r)

hrefs :: Text -> [Text]
hrefs html = [T.takeWhile (/= '"') piece | piece <- drop 1 (T.splitOn "href=\"" html)]

count :: Text -> Text -> Int
count needle hay = length (T.splitOn needle hay) - 1

-- | Whether any tag carries an @onmouseover=@ attribute of its own.
breaksOut :: Text -> Bool
breaksOut html = any bad [T.takeWhile (/= '>') t | t <- drop 1 (T.splitOn "<" html)]
  where
    bad tag = any (`T.isInfixOf` tag) [" onmouseover=", "\"onmouseover=", "\tonmouseover=", "\nonmouseover="]

keyIn :: Text -> Maybe Text
keyIn html = case [k | piece <- drop 1 (T.splitOn "msk_" html), let k = T.take 52 piece, T.length k == 52, T.all (\c -> isAsciiLower c || c `elem` ['2' .. '7']) k] of
  k : _ -> Just ("msk_" <> k)
  [] -> Nothing

spec :: Spec
spec = describe "web" $ do
  it "every error code has a message in both languages, and the API's codes are all covered" $ do
    forM_ Messages.table $ \(c, pt, en) -> do
      (c, T.null pt, T.null en) `shouldBe` (c, False, False)
      (c, pt == en) `shouldBe` (c, False)
    let errors = snd (T.breakOn "## Errors" StudyApi.skill)
        listed = [w | piece <- drop 1 (T.splitOn "`" errors) `every` 2, let w = piece, not (T.null w), T.all (\x -> isAsciiLower x || x == '_') w, w /= "id"]
        every xs n = [x | (i, x) <- zip [0 :: Int ..] xs, i `mod` n == 0]
    listed `shouldNotBe` []
    forM_ (listed <> ["too_large", "duplicate", "quota_exceeded", "account_too_new", "rate_limited", "unauthorized", "too_soon", "daily_limit", "csrf"]) $ \c ->
      (c, c `elem` Messages.codes) `shouldBe` (c, True)

  it "a visitor sees the login button; a logged-in one sees the form with a token, both with the headers and no script" $ withSite $ \site -> do
    out <- page site "/submit" Nothing
    out.status `shouldBe` 200
    let html = bodyText out
    html `shouldSatisfy` T.isInfixOf "/auth/github/login"
    html `shouldNotSatisfy` T.isInfixOf "<form method=\"POST\" action=\"/submit\""
    header out "Cache-Control" `shouldSatisfy` maybe False (BC.isInfixOf "no-store")
    header out "Content-Security-Policy" `shouldSatisfy` isJust
    html `shouldSatisfy` T.isInfixOf "/api/v1/skill.md"
    (c, csrf) <- loggedIn site 1 "ana"
    inn <- page site "/en/submit" (Just c)
    let p = bodyText inn
    p `shouldSatisfy` T.isInfixOf "action=\"/en/submit\""
    p `shouldSatisfy` T.isInfixOf ("name=\"csrf\" value=\"" <> csrf <> "\"")
    p `shouldNotSatisfy` T.isInfixOf "<script"
    p `shouldNotSatisfy` T.isInfixOf "style="

  it "the form publishes through the intake: the study page shows the file's hash, and the file is stored" $ withSite $ \site -> do
    (c, csrf) <- loggedIn site 1 "ana"
    i <- publish site c csrf goodFields validPdf
    length <$> filesUnder site.config.studies >>= (`shouldBe` 1)
    p <- page site ("/studies/" <> TE.encodeUtf8 i) Nothing
    forM_ [sha validPdf, "https://orcid.org/0000-0002-1825-0097", "/report/"] $ \n -> bodyText p `shouldSatisfy` T.isInfixOf n
    bodyText p `shouldSatisfy` T.isInfixOf "<p class=\"notice\" role=\"note\"><span class=\"status warn\"><i></i>sem revisão</span>"
    header p "Cache-Control" `shouldSatisfy` maybe False (BC.isInfixOf "max-age=60")
    (.status) <$> page site ("/studies/" <> TE.encodeUtf8 i <> ".pdf") Nothing >>= (`shouldBe` 200)
    again <- postSubmit site "/submit" c (Just same) (studyForm (Just csrf) goodFields (Just (pdfBytes "" 5)))
    again.status `shouldBe` 429
    bodyText again `shouldSatisfy` T.isInfixOf "um envio por conta a cada 10 minutos"

  it "a post without the token, with a wrong token or from another site is 403 and stores nothing" $ withSite $ \site -> do
    (c, csrf) <- loggedIn site 1 "ana"
    forM_ [(Nothing, same), (Just "0000", same), (Just csrf, "https://evil.example")] $ \(token, origin) -> do
      r <- postSubmit site "/submit" c (Just origin) (studyForm token goodFields (Just validPdf))
      r.status `shouldBe` 403
    filesUnder site.config.studies >>= (`shouldBe` [])
    StudyStore.listStudies site.config.db Nothing Nothing Nothing 10 >>= (`shouldBe` []) . map (.id)
    outCookie <- send site (request "POST" "/submit" Nothing (Just same) (studyForm (Just csrf) goodFields (Just validPdf)))
    outCookie.status `shouldBe` 303
    header outCookie "Location" `shouldSatisfy` maybe False (BC.isInfixOf "/auth/github/login")

  it "errors come back all at once, next to the fields, in the page language" $ withSite $ \site -> do
    (c, csrf) <- loggedIn site 1 "ana"
    let bad = [("title", "no"), ("authors", "Ana | 0000-0002-1825-0098"), ("area", "mars"), ("ai_contribution", "drafting")]
    pt <- postSubmit site "/submit" c (Just same) (studyForm (Just csrf) bad (Just "x"))
    pt.status `shouldBe` 400
    forM_ ["escreva pelo menos 5 caracteres", "o ORCID iD não é válido", "preencha este campo", "este arquivo não é um PDF", "value=\"no\""] $ \n ->
      bodyText pt `shouldSatisfy` T.isInfixOf n
    en <- postSubmit site "/en/submit" c (Just same) (studyForm (Just csrf) bad (Just "x"))
    bodyText en `shouldSatisfy` T.isInfixOf "write at least 5 characters"
    filesUnder site.config.studies >>= (`shouldBe` [])

  it "study text is escaped in the page, the list and the feed; the feed is Atom" $ withSite $ \site -> do
    (c, csrf) <- loggedIn site 1 "ana"
    let evil = "<script>alert(1)</script> \"onmouseover=\"alert(2)"
        fields =
          [ ("title", "T " <> evil),
            ("authors", "Ana " <> evil),
            ("abstract", T.replicate 3 (evil <> " ") <> T.replicate 12 "padding text. "),
            ("area", "rio"),
            ("topic", "water-quality"),
            ("sources", "https://example.org/a?x=%22onmouseover=1&y=<b>"),
            ("repository", "https://example.org/r?q=\"onmouseover=3"),
            ("rights", "true"),
            ("ai_contribution", "drafting"),
            ("ai_models", evil),
            ("ai_process", evil)
          ]
    r <- postSubmit site "/submit" c (Just same) (studyForm (Just csrf) fields (Just validPdf))
    let i = TE.encodeUtf8 (idFrom r)
    forM_ ["/studies/" <> i, "/en/studies/" <> i, "/studies", "/studies.atom"] $ \url -> do
      html <- bodyText <$> page site url Nothing
      (url, "<script>alert" `T.isInfixOf` html, breaksOut html, "<b>" `T.isInfixOf` html) `shouldBe` (url, False, False, False)
    feed <- page site "/studies.atom" Nothing
    bodyText feed `shouldSatisfy` T.isInfixOf "<feed xmlns=\"http://www.w3.org/2005/Atom\">"
    fmap (BC.takeWhile (/= ';')) (header feed "Content-Type") `shouldBe` Just "application/atom+xml"
    count "<entry>" (bodyText feed) `shouldBe` 1

  it "the list hides hidden studies, filters and pages; a tombstone has no text, noindex, and its file is gone" $ withSite $ \site -> do
    (c, csrf) <- loggedIn site 1 "ana"
    i <- publish site c csrf goodFields validPdf
    let ib = TE.encodeUtf8 i
    bodyText <$> page site "/studies" Nothing >>= (`shouldSatisfy` T.isInfixOf i)
    bodyText <$> page site "/studies?area=salvador" Nothing >>= (`shouldNotSatisfy` T.isInfixOf i)
    acc <- bodyText <$> page site "/account" (Just c)
    acc `shouldSatisfy` T.isInfixOf ("/account/withdraw/" <> i)
    acc `shouldSatisfy` T.isInfixOf "noindex"
    no <- postSubmit site ("/account/withdraw/" <> ib) c (Just same) (form [("csrf", "bad")])
    no.status `shouldBe` 403
    yes <- postSubmit site ("/account/withdraw/" <> ib) c (Just same) (form [("csrf", csrf)])
    yes.status `shouldBe` 303
    tomb <- page site ("/studies/" <> ib) Nothing
    tomb.status `shouldBe` 200
    forM_ ["withdrawn by the author", sha validPdf, "name=\"robots\" content=\"noindex\""] $ \n -> bodyText tomb `shouldSatisfy` T.isInfixOf n
    forM_ ["Enterococcus", i <> ".pdf"] $ \n -> bodyText tomb `shouldNotSatisfy` T.isInfixOf n
    (.status) <$> page site ("/studies/" <> ib <> ".pdf") Nothing >>= (`shouldBe` 404)
    bodyText <$> page site "/studies" Nothing >>= (`shouldNotSatisfy` T.isInfixOf i)
    (.status) <$> page site "/studies/aaaaaaaaaa" Nothing >>= (`shouldBe` 404)

  it "the account page needs a session; a key is shown once; revoke and logout work" $ withSite $ \site -> do
    (.status) <$> page site "/account" Nothing >>= (`shouldBe` 303)
    (c, csrf) <- loggedIn site 1 "ana"
    made <- postSubmit site "/account/keys" c (Just same) (form [("csrf", csrf)])
    let Just key = keyIn (bodyText made)
    header made "Cache-Control" `shouldSatisfy` maybe False (BC.isInfixOf "no-store")
    isJust <$> StudyStore.verifyKey site.config.db key >>= (`shouldBe` True)
    bodyText <$> page site "/account" (Just c) >>= (`shouldNotSatisfy` T.isInfixOf key)
    k : _ <- StudyStore.listKeys site.config.db 1
    revoked <- postSubmit site (BC.pack ("/account/keys/" <> show k.id <> "/revoke")) c (Just same) (form [("csrf", csrf)])
    revoked.status `shouldBe` 303
    isNothing <$> StudyStore.verifyKey site.config.db key >>= (`shouldBe` True)
    out <- postSubmit site "/logout" c (Just same) (form [("csrf", csrf)])
    out.status `shouldBe` 303
    (.status) <$> page site "/account" (Just c) >>= (`shouldBe` 303)

  it "a report stores the reason and the time and no address; the honeypot stores nothing; no login needed" $ withSite $ \site -> do
    (c, csrf) <- loggedIn site 1 "ana"
    i <- publish site c csrf goodFields validPdf
    let ib = TE.encodeUtf8 i
        report origin fields = send site (request "POST" ("/report/" <> ib) Nothing (Just origin) (form fields))
    p <- page site ("/report/" <> ib) Nothing
    p.status `shouldBe` 200
    bodyText p `shouldNotSatisfy` T.isInfixOf "type=\"email\""
    (.status) <$> report same [("reason", "wrong"), ("details", "the numbers differ"), ("website", "")] >>= (`shouldBe` 200)
    (.status) <$> report same [("reason", "spam"), ("website", "x")] >>= (`shouldBe` 200)
    StudyStore.countReports site.config.db i >>= (`shouldBe` 1)
    (.status) <$> report same [("reason", "nope")] >>= (`shouldBe` 400)
    (.status) <$> page site "/report/aaaaaaaaaa" Nothing >>= (`shouldBe` 404)
    (.status) <$> report "https://evil.example" [("reason", "spam")] >>= (`shouldBe` 403)
    l <- T.unlines <$> logLines site
    l `shouldNotSatisfy` T.isInfixOf "127.0.0.1"

  it "every page has one h1, no script, no inline style; public pages pair their languages; private ones are noindex" $ withSite $ \site -> do
    (c, csrf) <- loggedIn site 1 "ana"
    i <- publish site c csrf goodFields validPdf
    forM_ [("/submit", True), ("/studies", True), ("/studies/" <> i, True), ("/account", False), ("/report/" <> i, False)] $ \(p, canonical) ->
      forM_ ["", "/en"] $ \prefix -> do
        html <- bodyText <$> page site (TE.encodeUtf8 (prefix <> p)) (Just c)
        let wh = prefix <> p
        (wh, count "<h1" html, "<script" `T.isInfixOf` html, " style=" `T.isInfixOf` html) `shouldBe` (wh, 1, False, False)
        html `shouldSatisfy` T.isInfixOf ("<html lang=\"" <> (if prefix == "" then "pt-BR" else "en") <> "\">")
        if canonical
          then forM_ ["rel=\"canonical\" href=\"https://marola.dev" <> prefix <> p <> "\"", "hreflang=\"pt-BR\" href=\"https://marola.dev" <> p <> "\"", "hreflang=\"en\" href=\"https://marola.dev/en" <> p <> "\""] $ \n ->
            (wh, n `T.isInfixOf` html) `shouldBe` (wh, True)
          else (wh, "content=\"noindex\"" `T.isInfixOf` html) `shouldBe` (wh, True)
        (wh, (prefix <> "/studies") `elem` hrefs html, (prefix <> "/submit") `elem` hrefs html) `shouldBe` (wh, True, True)

  it "a board reason is escaped on the tombstone page and in the API" $ withSite $ \site -> do
    (c, csrf) <- loggedIn site 1 "ana"
    i <- publish site c csrf goodFields validPdf
    now <- readIORef site.clock
    StudyStore.hide site.config.db now i "<script>alert(1)</script> \"onmouseover=x & <b>" >>= (`shouldBe` True)
    forM_ ["/studies/" <> i, "/en/studies/" <> i] $ \p -> do
      html <- bodyText <$> page site (TE.encodeUtf8 p) Nothing
      html `shouldNotSatisfy` T.isInfixOf "<script>alert"
      html `shouldSatisfy` T.isInfixOf "&amp; &lt;b&gt;"
      html `shouldSatisfy` T.isInfixOf "&lt;script&gt;alert(1)&lt;/script&gt;"
    json <- bodyText <$> page site ("/api/v1/studies/" <> TE.encodeUtf8 i) Nothing
    json `shouldNotSatisfy` T.isInfixOf "<script>"
    json `shouldSatisfy` T.isInfixOf "\\u003cscript\\u003e"

  it "deleting the account needs the typed login, hides the studies, detaches them and logs out" $ withSite $ \site -> do
    (c, csrf) <- loggedIn site 1 "Ana"
    i <- publish site c csrf goodFields validPdf
    now <- readIORef site.clock
    Right key <- StudyStore.issueKey site.config.db now 1
    let del fields = postSubmit site "/account/delete" c (Just same) (form fields)
    bodyText <$> page site "/account" (Just c) >>= (`shouldSatisfy` T.isInfixOf "/account/delete")
    (.status) <$> del [("confirm", "Ana"), ("csrf", "bad")] >>= (`shouldBe` 403)
    (.status) <$> del [("confirm", "someone"), ("csrf", csrf)] >>= (`shouldBe` 400)
    isJust <$> StudyStore.getAccount site.config.db 1 >>= (`shouldBe` True)
    fmap (.status) <$> StudyStore.getStudy site.config.db i >>= (`shouldBe` Just Public)
    yes <- del [("confirm", " ana "), ("csrf", csrf)]
    yes.status `shouldBe` 303
    setCookieHeader yes "__Host-msess" `shouldSatisfy` maybe False (BC.isPrefixOf "__Host-msess=;")
    isNothing <$> StudyStore.getAccount site.config.db 1 >>= (`shouldBe` True)
    isNothing <$> StudyStore.verifyKey site.config.db key >>= (`shouldBe` True)
    (.status) <$> page site "/account" (Just c) >>= (`shouldBe` 303)
    Just study <- StudyStore.getStudy site.config.db i
    (study.status, study.hiddenReason, study.authorLogin) `shouldBe` (Hidden, Just "account deleted by the author", "deleted")
    study.authorGithubId `shouldSatisfy` (< 0)
    length <$> filesUnder site.config.studies >>= (`shouldBe` 1)
    bodyText <$> page site ("/studies/" <> TE.encodeUtf8 i) Nothing >>= (`shouldSatisfy` T.isInfixOf "account deleted by the author")
    (.status) <$> page site ("/studies/" <> TE.encodeUtf8 i <> ".pdf") Nothing >>= (`shouldBe` 404)
    (c2, csrf2) <- loggedIn site 1 "Ana"
    StudyStore.listByAuthor site.config.db 1 >>= (`shouldBe` []) . map (.id)
    StudyStore.listKeys site.config.db 1 >>= (`shouldBe` []) . map (.id)
    bodyText <$> page site "/account" (Just c2) >>= (`shouldNotSatisfy` T.isInfixOf i)
    StudyStore.unhide site.config.db i >>= (`shouldBe` False)
    again <- publish site c2 csrf2 goodFields validPdf
    again `shouldNotBe` i
