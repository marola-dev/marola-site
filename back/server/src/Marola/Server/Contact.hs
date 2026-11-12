-- | The contact form: @POST /contact@ stores the message in SQLite. The board reads it with
-- @marola-server inbox@.
module Marola.Server.Contact (validateEmail, validateMessage, sameSite, authority, handle) where

import Control.Exception (try)
import Data.Char (generalCategory, isAlphaNum, isAscii, isDigit, isSpace, GeneralCategory (Control))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Marola.Server.Config (Config (..))
import Marola.Server.Http
import Marola.Server.Store qualified as Store
import Marola.Utf16 qualified as U
import Network.HTTP.Types
import Network.Wai

-- | One @\@@, no spaces, quotes, brackets or commas in the local part, and a dotted domain of
-- letters, digits and hyphens. Not the whole RFC: a mistyped address must fail, and nothing here
-- sends mail, so an exotic one is no loss.
validateEmail :: Text -> Either Text Text
validateEmail raw =
  let email = T.strip raw
      (local, rest) = T.breakOn "@" email
      domain = T.drop 1 rest
      localOk = U.len local >= 1 && U.len local <= 64 && T.all (\c -> not (isSpace c) && c `notElem` ("@<>,;:\"()[]\\" :: String)) local
      label l = not (T.null l) && T.all (\c -> isAscii c && (isAlphaNum c || c == '-')) l && T.head l /= '-' && T.last l /= '-'
      labels = T.splitOn "." domain
      domainOk = not (T.null rest) && length labels >= 2 && all label labels
   in if U.len email == 0 || U.len email > 254 || not localOk || not domainOk then Left "email" else Right email

-- | Tab and the newlines are the only control characters a message may carry: the board prints the
-- body on a terminal, and NUL breaks SQLite text.
validateMessage :: Text -> Either Text Text
validateMessage raw =
  let message = T.strip raw
      bad c = generalCategory c == Control && c `notElem` ("\n\r\t" :: String)
   in if U.len message < 10 || U.len message > 4000 || T.any bad message then Left "message" else Right message

-- | The authority of an absolute http or https URL: host and port, the
-- default port left out, lower case.
authority :: Text -> Maybe Text
authority value = do
  (scheme, rest) <- case T.breakOn "://" value of
    (sc, r) | not (T.null r) -> Just (T.toLower sc, T.drop 3 r)
    _ -> Nothing
  if scheme /= "http" && scheme /= "https" then Nothing else Just ()
  let auth0 = T.takeWhile (`notElem` ("/?#" :: String)) rest
      auth = snd (T.breakOnEnd "@" auth0)
      (host, port) =
        if "[" `T.isPrefixOf` auth
          then let (h, p) = T.breakOn "]" auth in (h <> T.take 1 p, T.drop 1 (T.drop 1 p))
          else let (h, p) = T.breakOn ":" auth in (h, T.drop 1 p)
      hasPort = if "[" `T.isPrefixOf` auth then ":" `T.isPrefixOf` T.drop 1 (snd (T.breakOn "]" auth)) else ":" `T.isInfixOf` auth
  if T.null host || T.any (\c -> isSpace c || c `elem` ("<>\"{}|\\^`" :: String)) host then Nothing else Just ()
  portText <-
    if not hasPort
      then Just ""
      else
        if not (T.null port) && T.all isDigit port && T.length port <= 5 && (read (T.unpack port) :: Int) <= 65535
          then Just port
          else Nothing
  let defaultPort = if scheme == "http" then "80" else "443"
      p = if T.null portText || (read (T.unpack portText) :: Int) == read defaultPort then "" else ":" <> T.pack (show (read (T.unpack portText) :: Int))
  pure (T.toLower host <> p)

-- | The Host header and the Origin (or, failing it, the Referer) must name the same site. A browser
-- always sends Origin on a cross-site POST and a page cannot forge it, so no token is needed (the
-- page is static and cannot carry one). nginx must pass the public host: @proxy_set_header Host $host@.
sameSite :: Text -> Text -> Text -> Bool
sameSite host origin referer =
  let claimed = if T.null origin then referer else origin
   in case (authority claimed, authority ("https://" <> host)) of
        (Just theirs, Just ours) -> T.toLower theirs == T.toLower ours
        _ -> False

reply :: Status -> Text -> Response
reply st t = plain st (t <> "\n")

-- | @POST /contact@ and @POST /en/contact@.
handle :: Env -> Request -> IO Response
handle env req
  | not (sameSite (header req "Host") (header req "Origin") (header req "Referer")) = pure (reply status403 "forbidden")
  | not (isContentType req "application/x-www-form-urlencoded") = pure (reply status415 "unsupported media type")
  | otherwise = do
      r <- try (readForm req)
      case r of
        Left BodyTooLarge -> pure (reply status413 "bad request")
        Right (Left _) -> pure (reply status400 "bad request")
        Right (Right form) -> do
          let field n = Map.findWithDefault "" n form
          if field "website" /= ""
            then -- A bot fills the hidden field. It gets a plain 200 and nothing is stored.
              pure (reply status200 "ok")
            else case (validateEmail (field "email"), validateMessage (field "message")) of
              (Right email, Right message) -> do
                now <- env.clock
                i <- Store.insert env.config.db now email message
                -- The id only: the address and the text are personal data.
                env.logger "Marola.Contact" Information ("contact message stored " <> tshow i)
                -- The page that thanks the visitor is a static file, in the language of the path posted to.
                let prefix = if isEnglish (TE.decodeUtf8Lenient (rawPathInfo req)) then "/en" else ""
                pure (responseLBS status303 [(hLocation, TE.encodeUtf8 (prefix <> "/contact-sent.html"))] "")
              (Left bad, _) -> pure (reply status400 ("invalid " <> bad))
              (_, Left bad) -> pure (reply status400 ("invalid " <> bad))
  where
    isEnglish p = let l = T.toLower p in l == "/en" || "/en/" `T.isPrefixOf` l
