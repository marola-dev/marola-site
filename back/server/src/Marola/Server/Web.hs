-- | The human side of the study API: the pages, the forms and their POSTs. A POST needs the same site (Origin) and, when it changes an account, a session
-- and its CSRF token. The form of @/submit@ goes through 'StudyApi.intake', the same function as the API.
module Marola.Server.Web (routes) where

import Control.Exception (try)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.Int (Int64)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Marola.Layout (Language (..), Locale (..))
import Marola.Server.Config (Config (..))
import Marola.Server.Contact (sameSite)
import Marola.Server.Http
import Marola.Server.Session (Live (..))
import Marola.Server.Session qualified as Session
import Marola.Server.StudyApi qualified as StudyApi
import Marola.Server.StudyStore (Account (..), KeyError (..))
import Marola.Server.StudyStore qualified as StudyStore
import Marola.Server.Views qualified as Views
import Marola.Study
import Marola.Utf16 qualified as U
import Network.HTTP.Types
import Network.Wai

language :: Request -> Language
language req = languageOf (decodedPath req)

localeOf :: Env -> Request -> Locale
localeOf env req = Locale {catalog = env.catalog, language = language req}

page :: Int -> ByteString -> Text -> Response
page st = html (toEnum st)

redirect :: Text -> Response
redirect location = redirect303 (TE.encodeUtf8 location) []

refuse :: Env -> Request -> Int -> (Text, Text) -> (Text, Text) -> Response
refuse env req st pt en =
  let loc = localeOf env req
      (title, sentence) = if loc.language == En then en else pt
   in page st "no-store" (Views.messagePage loc title sentence)

forbidden :: Env -> Request -> Response
forbidden env req =
  refuse
    env
    req
    403
    ("Pedido recusado", "O pedido não veio deste site ou a sessão do formulário venceu. Recarregue a página e tente de novo.")
    ("Request refused", "The request did not come from this site, or the form session ended. Reload the page and try again.")

notFound :: Env -> Request -> Response
notFound env req = refuse env req 404 ("Não encontrado", "Não há nada neste endereço.") ("Not found", "There is nothing at this address.")

fromSameSite :: Request -> Bool
fromSameSite req = sameSite (header req "Host") (header req "Origin") (header req "Referer")

session :: Env -> Request -> IO (Maybe Live)
session env req = do
  now <- env.clock
  Session.current env.config.db now (cookie req (Session.sessionCookie env.config.dev))

toLogin :: Env -> Request -> Response
toLogin env req = redirect (Views.loginPath (localeOf env req))

-- | The fields of a urlencoded POST, or 'Nothing' when the body is not a form or too big.
form :: Request -> IO (Maybe (Map.Map Text Text))
form req = do
  r <- try (readForm req)
  pure $ case r of
    Right (Right f) -> Just f
    Right (Left _) -> Nothing
    Left BodyTooLarge -> Nothing

-- | A POST that changes an account: same site, a session, a valid token. Anything else is refused.
accountPost :: Env -> Request -> (Live -> Map.Map Text Text -> IO Response) -> IO Response
accountPost env req act
  | not (fromSameSite req) = pure (forbidden env req)
  | otherwise = do
      live <- session env req
      case live of
        Nothing -> pure (toLogin env req)
        Just l -> do
          f <- form req
          case f >>= Map.lookup "csrf" of
            Just token | Session.csrfValid env.csrfKey l.hash token -> act l (maybe Map.empty id f)
            _ -> pure (forbidden env req)

accountView :: Env -> Request -> Live -> Maybe Text -> Bool -> Bool -> IO Response
accountView env req live newKey keyError deleteError = do
  let db = env.config.db
  keys <- StudyStore.listKeys db live.account.githubId
  studies <- StudyStore.listByAuthor db live.account.githubId
  pure $
    page
      (if deleteError then 400 else 200)
      "no-store"
      (Views.accountPage (localeOf env req) live.account (Session.csrfToken env.csrfKey live.hash) keys studies newKey keyError deleteError)

-- ---- handlers ------------------------------------------------------------------------------------

submitGet :: Env -> Request -> Params -> IO Response
submitGet env req _ = do
  live <- session env req
  let csrf = (\l -> Session.csrfToken env.csrfKey l.hash) <$> live
  pure (page 200 "no-store" (Views.submitPage (localeOf env req) csrf Map.empty []))

submitPost :: Env -> Request -> Params -> IO Response
submitPost env req _
  | not (fromSameSite req) = pure (forbidden env req)
  | otherwise = do
      live <- session env req
      case live of
        Nothing -> pure (toLogin env req)
        Just l -> do
          let loc = localeOf env req
              csrf = Session.csrfToken env.csrfKey l.hash
              gate f = maybe False (Session.csrfValid env.csrfKey l.hash) (Map.lookup "csrf" f)
          (outcome, fields) <- StudyApi.intake env req l.account ("session:" <> tshow l.account.githubId) (Set.fromList ["csrf"]) gate
          pure $ case outcome of
            StudyApi.Created record -> redirect (Views.url loc (urlOf record.id))
            StudyApi.Failed f
              | any (\e -> e.code == "csrf") f.errors -> forbidden env req
              | otherwise ->
                  -- A duplicate shows the old study's link next to the error.
                  let errs = f.errors <> maybe [] (\i -> [FieldError "id" "duplicate" (urlOf i)]) f.existing
                      extra = maybe [] (\v -> [("Retry-After", TE.encodeUtf8 v)]) f.retryAfter
                   in mapResponseHeaders (<> extra) (page f.status "no-store" (Views.submitPage loc (Just csrf) fields errs))
            StudyApi.DryRun _ _ -> page 200 "no-store" (Views.submitPage loc (Just csrf) fields [])

studiesGet :: Env -> Request -> Params -> IO Response
studiesGet env req _ = do
  let q = queryText req
      ar = parseArea (q "area")
      tp = parseTopic (q "topic")
      before = let b = q "before" in if validId b then Just b else Nothing
      limit = 20
  studies <- StudyStore.listStudies env.config.db ar tp before limit
  let next = if length studies == limit then Just (last studies).id else Nothing
  pure (page 200 "public, max-age=60" (Views.studiesPage (localeOf env req) studies ar tp next))

studyOrPdf :: Env -> Request -> Params -> IO Response
studyOrPdf env req params = do
  let file = Map.findWithDefault "" "file" params
  if ".pdf" `T.isSuffixOf` file
    then StudyApi.pdf env file
    else do
      record <- if validId file then StudyStore.getStudy env.config.db file else pure Nothing
      pure $ case record of
        Just r -> page 200 "public, max-age=60" (Views.studyPage (localeOf env req) r)
        Nothing -> notFound env req

atom :: Env -> Request -> Params -> IO Response
atom env _ _ = do
  studies <- StudyStore.listStudies env.config.db Nothing Nothing Nothing 50
  pure $
    responseLBS
      status200
      [(hContentType, "application/atom+xml; charset=utf-8"), (hCacheControl, "public, max-age=60")]
      (fromText (Views.atom studies))
  where
    fromText = BL.fromStrict . TE.encodeUtf8

accountGet :: Env -> Request -> Params -> IO Response
accountGet env req _ = do
  live <- session env req
  case live of
    Nothing -> pure (toLogin env req)
    Just l -> accountView env req l Nothing False False

createKey :: Env -> Request -> Params -> IO Response
createKey env req _ = accountPost env req $ \l _ -> do
  now <- env.clock
  r <- StudyStore.issueKey env.config.db now l.account.githubId
  case r of
    Right key -> accountView env req l (Just key) False False
    Left TooManyKeys -> accountView env req l Nothing True False

revokeKey :: Env -> Request -> Params -> IO Response
revokeKey env req params = accountPost env req $ \l _ -> do
  now <- env.clock
  case parseInt64 (Map.findWithDefault "" "id" params) of
    Just i -> () <$ StudyStore.revokeKey env.config.db now l.account.githubId i
    Nothing -> pure ()
  pure (redirect (Views.url (localeOf env req) "/account"))

withdraw :: Env -> Request -> Params -> IO Response
withdraw env req params = accountPost env req $ \l _ -> do
  now <- env.clock
  let i = Map.findWithDefault "" "id" params
  if validId i then () <$ StudyStore.withdraw env.config.db now l.account.githubId i else pure ()
  pure (redirect (Views.url (localeOf env req) "/account"))

home :: Request -> Text
home req = if language req == En then "/?lang=en" else "/"

clearSession :: Env -> Response -> Response
clearSession env = mapResponseHeaders (<> [("Set-Cookie", Session.clearCookie env.config.dev (Session.sessionCookie env.config.dev))])

logout :: Env -> Request -> Params -> IO Response
logout env req _ = accountPost env req $ \l _ -> do
  _ <- StudyStore.deleteSession env.config.db l.token
  pure (clearSession env (redirect (home req)))

-- | The author deletes the account: a typed confirmation of the login, then
-- 'StudyStore.deleteAccount', and the session cookie is cleared. The studies stay as tombstones.
deleteAccount :: Env -> Request -> Params -> IO Response
deleteAccount env req _ = accountPost env req $ \l f -> do
  let typed = T.strip (Map.findWithDefault "" "confirm" f)
  if T.toUpper typed == T.toUpper l.account.login
    then do
      now <- env.clock
      _ <- StudyStore.deleteAccount env.config.db now l.account.githubId
      env.logger "Marola.Web" Information "account deleted"
      pure (clearSession env (redirect (home req)))
    else accountView env req l Nothing False True

reportGet :: Env -> Request -> Params -> IO Response
reportGet env req params = do
  let i = Map.findWithDefault "" "id" params
  r <- if validId i then StudyStore.getStudy env.config.db i else pure Nothing
  pure $ case r of
    Just _ -> page 200 "no-store" (Views.reportPage (localeOf env req) i False)
    Nothing -> notFound env req

reasonCodes :: [Text]
reasonCodes = [c | (c, _, _) <- Views.reasons]

reportPost :: Env -> Request -> Params -> IO Response
reportPost env req params
  | not (fromSameSite req) = pure (forbidden env req)
  | otherwise = do
      let i = Map.findWithDefault "" "id" params
          loc = localeOf env req
      f <- form req
      case f of
        Nothing -> pure (forbidden env req)
        Just fs -> do
          let field n = Map.findWithDefault "" n fs
          study <- if validId i then StudyStore.getStudy env.config.db i else pure Nothing
          if
            -- The honeypot: a bot gets the thank-you page and nothing is stored.
            | field "website" /= "" -> pure (page 200 "no-store" (Views.thanksPage loc))
            | Nothing <- study -> pure (notFound env req)
            | otherwise -> do
                let reason = cleanText (field "reason")
                    details = U.take 1000 (cleanText (field "details"))
                if reason `notElem` reasonCodes || (reason == "other" && T.null details)
                  then pure (page 400 "no-store" (Views.reportPage loc i True))
                  else do
                    now <- env.clock
                    _ <- StudyStore.insertReport env.config.db now i (if T.null details then reason else reason <> ": " <> details)
                    -- The study id only: no address, no text.
                    env.logger "Marola.Web" Information ("report stored " <> i)
                    pure (page 200 "no-store" (Views.thanksPage loc))

parseInt64 :: Text -> Maybe Int64
parseInt64 t =
  let s = T.strip t
      (sign, digits) = case T.uncons s of
        Just ('+', r) -> (1, r)
        Just ('-', r) -> (-1, r)
        _ -> (1, s)
   in if not (T.null digits) && T.all (`elem` ['0' .. '9']) digits && T.length digits <= 19
        then let v = sign * read (T.unpack digits) :: Integer in if abs v <= 9223372036854775807 then Just (fromInteger v) else Nothing
        else Nothing

-- | Each pattern under @""@ and @"/en"@.
routes :: [Route]
routes =
  concat
    [ both "GET" "/submit" False submitGet
    , both "POST" "/submit" False submitPost
    , both "GET" "/studies" False studiesGet
    , both "GET" "/studies/{file}" False studyOrPdf
    , both "GET" "/account" False accountGet
    , both "POST" "/account/keys" False createKey
    , both "POST" "/account/keys/{id}/revoke" False revokeKey
    , both "POST" "/account/withdraw/{id}" False withdraw
    , both "POST" "/account/delete" False deleteAccount
    , both "POST" "/logout" False logout
    , both "GET" "/report/{id}" False reportGet
    , both "POST" "/report/{id}" True reportPost
    , [Route "GET" "/studies.atom" False atom]
    ]
  where
    both m p st h = [Route m (prefix <> p) st h | prefix <- ["", "/en"]]
