-- | The human side on the built server (MAROLA_DEV=1, a fake GitHub): log in through the real redirects
-- with a cookie jar, make a key, submit a PDF through the form with its CSRF token, read the study page
-- and compare its hash with `sha256sum`, report it, withdraw it, see the tombstone, delete the account.
module Marola.Tools.SmokeSubmit (main) where

import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.CaseInsensitive (CI)
import Data.Char (isDigit, isHexDigit, isLower)
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Marola.Tools.Client
import Network.HTTP.Client qualified as H
import Network.HTTP.Client.MultipartFormData (Part, PartM (..), partBS, partFileRequestBody)
import System.Exit (exitFailure)

base32 :: Char -> Bool
base32 x = isLower x || (x >= '2' && x <= '7')

csrfOf :: Text -> Maybe Text
csrfOf html = case T.breakOn "name=\"csrf\" value=\"" html of
  (_, rest) | T.null rest -> Nothing
  (_, rest) ->
    let v = T.takeWhile (/= '"') (T.drop (T.length "name=\"csrf\" value=\"") rest)
     in if T.length v == 64 && T.all (\x -> isHexDigit x && not (x >= 'A' && x <= 'F')) v then Just v else Nothing

-- | The first @msk_@ followed by 52 base32 characters.
keyOf :: Text -> Maybe Text
keyOf html = case [k | chunk <- drop 1 (T.splitOn "msk_" html), let k = T.take 52 chunk, T.length k == 52, T.all base32 k] of
  (k : _) -> Just ("msk_" <> k)
  [] -> Nothing

main :: [String] -> IO ()
main = \case
  [base, pdfPath, expectedSha] -> run base pdfPath (T.pack expectedSha)
  _ -> fail "usage: marola-tools smoke-submit <base> <pdf> <sha256>"

run :: String -> FilePath -> Text -> IO ()
run base pdfPath expectedSha = do
  m <- newManager
  c <- newChecks ""
  pdf <- B.readFile pdfPath
  jar <- newIORef (Map.empty :: Map.Map ByteString ByteString)
  let origin = BC.pack base
      check cond what = ok c cond what ""
      -- A request with the jar's cookies; each Set-Cookie of the answer updates the jar.
      go :: ByteString -> ByteString -> [(CI ByteString, ByteString)] -> H.RequestBody -> IO Res
      go method path hs reqBody = do
        cookies <- readIORef jar
        let cookie = [("cookie", B.intercalate "; " [k <> "=" <> v | (k, v) <- Map.toList cookies]) | not (Map.null cookies)]
        r <- send m base method path (hs <> cookie) reqBody
        mapM_ (modifyIORef' jar . setCookie) (hdrs "set-cookie" r)
        pure r
      setCookie line cookies =
        let pair = BC.takeWhile (/= ';') line
            (k, v) = BC.drop 1 <$> BC.break (== '=') pair
            lower = T.toLower (TE.decodeUtf8 line)
         in if "max-age=0" `T.isInfixOf` lower || "expires=thu, 01 jan 1970" `T.isInfixOf` lower then Map.delete k cookies else Map.insert k v cookies
      goGet path = go "GET" path [] mempty
      url = TE.encodeUtf8 . fromMaybe "" . hdr "location"
      post path fields = go "POST" path [("origin", origin), ("content-type", "application/x-www-form-urlencoded")] (H.RequestBodyBS (formEncode fields))
      -- A redirect to another host (the fake GitHub) is followed by hand with a client of its own.
      follow loc = do
        let (scheme, rest) = BC.breakSubstring "://" loc
            (host, path) = BC.break (== '/') (BC.drop 3 rest)
        r <- send m (BC.unpack (scheme <> "://" <> host)) "GET" (if B.null path then "/" else path) [] mempty
        mapM_ (modifyIORef' jar . setCookie) (hdrs "set-cookie" r)
        pure r
      relative loc = if "http" `B.isPrefixOf` loc then BC.dropWhile (/= '/') (BC.drop 3 (snd (BC.breakSubstring "://" loc))) else loc
      signIn = do
        l <- goGet "/auth/github/login"
        gh <- follow (url l)
        cb <- go "GET" (relative (url gh)) [] mempty
        pure (l, cb)
      txt = fmap text . goGet

  -- 1. Login through the redirects: the site, the fake GitHub, the callback.
  (login, callback) <- signIn
  let loc = fromMaybe "" (hdr "location" login)
  check (login.status == 302 && "/login/oauth/authorize?" `T.isInfixOf` loc) "login redirects to GitHub"
  check (not ("scope=" `T.isInfixOf` loc)) "login asks for no scope"
  check (callback.status == 303 && hdr "location" callback == Just "/account") "the callback starts a session and goes to /account"
  hasSession <- Map.member "msess" <$> readIORef jar
  check hasSession "the session cookie is set"

  account <- goGet "/account"
  let accountHtml = text account
      csrf = TE.encodeUtf8 (fromMaybe "" (csrfOf accountHtml))
  check (account.status == 200 && "smoke-sci" `T.isInfixOf` accountHtml && isJust (csrfOf accountHtml)) "/account shows the login and a CSRF token"
  check (hdr "cache-control" account == Just "no-store") "/account is no-store"

  -- 2. A key is shown once.
  made <- post "/account/keys" [("csrf", csrf)]
  let key = keyOf (text made)
  check (made.status == 200 && isJust key && hdr "cache-control" made == Just "no-store") "a key is shown on the answer, with no-store"
  again <- txt "/account"
  check (maybe False (\k -> not (k `T.isInfixOf` again)) key) "the key is not shown again"

  -- 3. No token, or another site: 403.
  noToken <- post "/account/keys" []
  check (noToken.status == 403) "a POST without the token is 403"
  evil <- go "POST" "/account/keys" [("origin", "https://evil.example"), ("content-type", "application/x-www-form-urlencoded")] (H.RequestBodyBS (formEncode [("csrf", csrf)]))
  check (evil.status == 403) "a POST from another origin is 403"

  -- 4. Submit through the form. The token comes first: a post without it never writes the file.
  let form withToken =
        [partBS "csrf" csrf | withToken]
          <> [ partBS "title" "Smoke test of the study form",
               partBS "authors" "Ana Silva | 0000-0002-1825-0097",
               partBS "abstract" (B.concat (replicate 5 "A smoke test study sent through the form. ")),
               partBS "area" "rio",
               partBS "topic" "data",
               partBS "rights" "true",
               partBS "ai_contribution" "none",
               (partFileRequestBody "pdf" "smoke.pdf" (H.RequestBodyBS pdf)) {partContentType = Just "application/pdf"}
             ] ::
          [Part]
      submit withToken = do
        cookies <- readIORef jar
        let cookie = [("cookie", B.intercalate "; " [k <> "=" <> v | (k, v) <- Map.toList cookies]) | not (Map.null cookies)]
        postMultipart m base "/submit" (("origin", origin) : cookie) (form withToken)
  denied <- submit False
  check (denied.status == 403) "the form without a token is 403"
  sent <- submit True
  let whereT = fromMaybe "" (hdr "location" sent)
      whereB = TE.encodeUtf8 whereT
      sid = T.takeWhileEnd (/= '/') whereT
      studyPath = maybe False (\i -> T.length i == 10 && T.all base32 i) (T.stripPrefix "/studies/" whereT)
  check (sent.status == 303 && studyPath) ("the form publishes and redirects to the study page (" <> T.pack (show sent.status) <> " " <> whereT <> ")")

  page <- goGet whereB
  check (page.status == 200 && expectedSha `T.isInfixOf` text page) "the study page shows the SHA-256 that sha256sum printed"
  file <- goGet (whereB <> ".pdf")
  check (file.status == 200 && BL.toStrict file.body == pdf) "the PDF link serves the same bytes"

  -- 5. Report it (no login needed: a request without the jar), then withdraw it.
  reported <- postForm m base (TE.encodeUtf8 ("/report/" <> sid)) [("origin", origin)] [("reason", "wrong"), ("details", "smoke"), ("website", "")]
  check (reported.status == 200) "a report is accepted with no login"
  withdrawn <- post (TE.encodeUtf8 ("/account/withdraw/" <> sid)) [("csrf", csrf)]
  check (withdrawn.status == 303) "withdraw redirects"
  tomb <- txt whereB
  check ("withdrawn by the author" `T.isInfixOf` tomb && expectedSha `T.isInfixOf` tomb && not ("Smoke test of the study form" `T.isInfixOf` tomb)) "the tombstone has the hash and the reason, no text"
  gone1 <- goGet (whereB <> ".pdf")
  check (gone1.status == 404) "the withdrawn file is not served"

  out <- post "/logout" [("csrf", csrf)]
  after <- goGet "/account"
  check (out.status == 303 && after.status == 303) "logout ends the session"

  -- 6. Delete the account: the typed login is needed, then keys, sessions and the account go, and a new
  -- login with the same GitHub id starts empty. The study stays as a tombstone with its hash.
  _ <- signIn
  html2 <- txt "/account"
  let csrf2 = TE.encodeUtf8 (fromMaybe "" (csrfOf html2))
  check (isJust (csrfOf html2) && "/account/delete" `T.isInfixOf` html2) "after a new login the account page has the delete form"
  wrong <- post "/account/delete" [("csrf", csrf2), ("confirm", "not-me")]
  still <- goGet "/account"
  check (wrong.status == 400 && still.status == 200) "a wrong typed login deletes nothing"
  deleted <- post "/account/delete" [("csrf", csrf2), ("confirm", "smoke-sci")]
  ended <- goGet "/account"
  check (deleted.status == 303 && ended.status == 303) "the typed login deletes the account and ends the session"
  _ <- signIn
  html3 <- txt "/account"
  let keyLabel = any (\w -> any (\chunk -> not (T.null chunk) && isDigit (T.head chunk)) (drop 1 (T.splitOn w html3))) ["Chave ", "Key "]
  check (not (sid `T.isInfixOf` html3) && not ("msk_" `T.isInfixOf` html3) && not keyLabel) "a login after the deletion is a fresh account: no study, no key"
  tomb2 <- txt whereB
  gone2 <- goGet (whereB <> ".pdf")
  check (expectedSha `T.isInfixOf` tomb2 && gone2.status == 404) "the study stays as a tombstone with its hash after the deletion"

  n <- failures c
  unless (n == 0) exitFailure
