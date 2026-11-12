-- | @/api/v1@: submit, list and read studies, and the PDF route.
-- Everything a client reads is built from "Marola.Study"; nothing it sends reaches a header, a log
-- line or a path except a validated id or hash.
module Marola.Server.StudyApi
  ( uploadLimit
  , apiPath
  , perKeyUnits
  , keyWindow
  , minAccountAge
  , gapBetween
  , realCost
  , dryCost
  , perDay
  , maxParts
  , maxFieldBytes
  , listDefault
  , listMax
  , tooLarge
  , Failure (..)
  , Outcome (..)
  , intake
  , failureResponse
  , submit
  , list
  , one
  , pdf
  , skill
  , skillResponse
  , route
  )
where

import Control.Exception (try)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (isDigit)
import Data.IORef
import Data.Int (Int64)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (NominalDiffTime, UTCTime, addUTCTime, diffUTCTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Marola.Json
import Marola.Server.Config (Config (..))
import Marola.Server.Http
import Marola.Server.Multipart qualified as M
import Marola.Server.PdfIntake qualified as PdfIntake
import Marola.Server.RateLimit qualified as RateLimit
import Marola.Server.StudyStore (Account (..))
import Marola.Server.StudyStore qualified as StudyStore
import Marola.Study
import Network.HTTP.Types hiding (Status)
import Network.HTTP.Types qualified as H
import Network.Wai
import System.Directory (doesFileExist)

-- | The body of the upload route: the file (20 MB), the text fields and the multipart framing.
uploadLimit :: Int64
uploadLimit = 21 * 1024 * 1024

apiPath :: Text
apiPath = "/api/v1/studies"

minAccountAge, keyWindow, gapBetween :: NominalDiffTime
minAccountAge = 7 * 86400
keyWindow = 60
gapBetween = 600

perKeyUnits, realCost, dryCost, maxParts, maxFieldBytes, listDefault, listMax :: Int
perKeyUnits = 90
realCost = 3
dryCost = 1
maxParts = 20
maxFieldBytes = 20000
listDefault = 20
listMax = 50

perDay :: Int64
perDay = 10

json :: H.Status -> ByteString -> Json -> [Header] -> Response
json st cache j = jsonResponse st cache (render j)

failJson :: H.Status -> Text -> Text -> Text -> [Header] -> Response
failJson st f c m = json st "no-store" (errorsJson [FieldError f c m])

-- | The 413 of the body guard, in the JSON shape of the API.
tooLarge :: Response
tooLarge = failJson status413 "request" "too_large" "the request is larger than 21 MB" []

-- ---- reading the upload --------------------------------------------------------------------------

data Upload = Upload
  { fields :: Map.Map Text Text
  , pdfResult :: Maybe (Either FieldError PdfIntake.Received)
  , errors :: [FieldError]
  , denied :: Bool
  -- ^ The gate refused the request: the web form posted no valid CSRF token.
  }

fieldNames :: Set.Set Text
fieldNames =
  Set.fromList
    ["title", "authors", "abstract", "area", "topic", "sources", "repository", "licence", "rights", "ai_models", "ai_contribution", "ai_process"]

-- | A text part, at most 'maxFieldBytes', strict UTF-8.
readText :: M.Part -> IO (Either Text Text)
readText part = go 0 []
  where
    go !n acc = do
      c <- part.body
      if
        | BS.null c -> pure $ case TE.decodeUtf8' (BS.concat (reverse acc)) of
            Right t -> Right t
            Left _ -> Left "invalid_utf8"
        | n + BS.length c > maxFieldBytes -> pure (Left "too_long")
        | otherwise -> go (n + BS.length c) (c : acc)

readUpload :: Config -> Bool -> IORef [PdfIntake.Received] -> M.Reader -> Set.Set Text -> (Map.Map Text Text -> Bool) -> IO Upload
readUpload config store pending reader extra gate = loop Map.empty Nothing [] Set.empty 0
  where
    finish fs p es d = pure Upload {fields = fs, pdfResult = p, errors = reverse es, denied = d || not (gate fs)}
    loop fs p es seen (parts :: Int) = do
      next <- M.nextPart reader
      case next of
        Nothing -> finish fs p es False
        Just part -> do
          let parts' = parts + 1
              name = TE.decodeUtf8Lenient (M.dispositionName part)
              add f c m = FieldError f c m : es
          if
            | parts' > maxParts -> finish fs p (add "request" "too_many_parts" ("at most " <> tshow maxParts <> " parts")) False
            -- The name is not echoed: it is attacker text.
            | Set.member name seen -> loop fs p (add "request" "duplicate_field" "a field name appears twice") seen parts'
            -- Nothing of the file is read: the token comes first in the form, and a post without it stores nothing.
            | name == "pdf" && not (gate fs) -> finish fs p es True
            | name == "pdf" -> do
                r <- PdfIntake.receive config store part.body
                -- Kept for the caller: a later part may fail, and the temp file must not stay.
                either (const (pure ())) (\x -> modifyIORef' pending (x :)) r
                loop fs (Just r) es (Set.insert name seen) parts'
            | Set.member name fieldNames || Set.member name extra -> do
                t <- readText part
                case t of
                  Right v -> loop (Map.insert name v fs) p es (Set.insert name seen) parts'
                  Left c ->
                    loop fs p (add name c (name <> (if c == "too_long" then " is too long" else " is not valid UTF-8"))) (Set.insert name seen) parts'
            | otherwise -> loop fs p (add "request" "unknown_field" "an unknown field was sent") (Set.insert name seen) parts'

-- ---- the intake: one path for the API and the web form -------------------------------------------

data Failure = Failure
  { status :: Int
  , retryAfter :: Maybe Text
  , errors :: [FieldError]
  , existing :: Maybe Text
  -- ^ The id of the study this account already sent (a 409).
  }

data Outcome
  = Failed Failure
  | DryRun PdfIntake.Received Submission
  | Created Record

failure :: Int -> Maybe Text -> Text -> Text -> Text -> Outcome
failure st retry f c m = Failed Failure {status = st, retryAfter = retry, errors = [FieldError f c m], existing = Nothing}

-- | Everything after the caller is known: account age, rates, the multipart body, the fields, the
-- file, the duplicate and the quota, then the insert. The API (bearer key) and the web form
-- (session) both call it. @rateKey@ names the caller in the per-minute limiter; @extra@ are the
-- form's fields besides the study's own (the web form's @csrf@); @gate@ sees the fields read so far
-- before the file is stored, and a 'False' stops the request with a 403. Returns the text fields
-- too, so the form can show them again.
intake :: Env -> Request -> Account -> Text -> Set.Set Text -> (Map.Map Text Text -> Bool) -> IO (Outcome, Map.Map Text Text)
intake env req account rateKey extra gate = do
  now <- env.clock
  let config = env.config
      db = config.db
      dry = queryText req "dry_run" == "1"
      stop o = pure (o, Map.empty)
      contentType = maybe "" id (lookup hContentType (requestHeaders req))
      tooNew = case iso8601ParseM (T.unpack account.createdGithubUtc) :: Maybe UTCTime of
        Just created -> diffUTCTime now created < minAccountAge
        Nothing -> True
  if tooNew
    then stop (failure 403 Nothing "request" "account_too_new" "the GitHub account must be at least 7 days old")
    else do
      rate <- RateLimit.take env.keyRates rateKey (if dry then dryCost else realCost) now
      case rate of
        Left _ ->
          stop (failure 429 (Just "60") "request" "rate_limited" "more than 30 requests a minute for this key (a dry run counts a third)")
        Right ()
          | not (isContentType req "multipart/form-data") ->
              stop (failure 415 Nothing "request" "unsupported_media_type" "send multipart/form-data")
          | otherwise -> do
              recent <- StudyStore.countSince db account.githubId (addUTCTime (negate gapBetween) now)
              daily <- StudyStore.countSince db account.githubId (addUTCTime (-86400) now)
              let boundary = fromMaybe "" (M.boundaryOf contentType)
              if
                | recent > 0 -> stop (failure 429 (Just "600") "request" "too_soon" "one submission per account every 10 minutes")
                | daily >= perDay -> stop (failure 429 (Just "86400") "request" "daily_limit" "10 submissions per account in 24 hours")
                | BS.null boundary || BS.length boundary > 70 ->
                    stop (failure 400 Nothing "request" "malformed_multipart" "the multipart boundary is missing or too long")
                | otherwise -> afterChecks now boundary
  where
    afterChecks now boundary = do
      let config = env.config
          dry = queryText req "dry_run" == "1"
      pending <- newIORef []
      reader <- M.newReader boundary (getRequestBodyChunk req)
      let discardPending = readIORef pending >>= mapM_ PdfIntake.discard
      r1 <- try (try (readUpload config (not dry) pending reader extra gate))
      outcome <- case r1 of
        Left BodyTooLarge -> discardPending >> pure (Left (413, "too_large", "the request is larger than 21 MB"))
        Right (Left (M.Malformed _)) -> discardPending >> pure (Left (400, "malformed_multipart", "the multipart body is malformed or over a limit"))
        Right (Right u) -> pure (Right u)
      case outcome of
        Left (st, c, m) -> pure (failure st Nothing "request" c m, Map.empty)
        Right upload
          | upload.denied -> do
              discardPending
              pure (failure 403 Nothing "request" "csrf" "the form token is missing or wrong", upload.fields)
          | otherwise -> decide now upload
    decide now upload = do
      let config = env.config
          dry = queryText req "dry_run" == "1"
          received = case upload.pdfResult of
            Just (Right r) -> Just r
            _ -> Nothing
          discard = maybe (pure ()) PdfIntake.discard received
          checked = validate (`Map.lookup` upload.fields)
          pdfErrors = case upload.pdfResult of
            Nothing -> [FieldError "pdf" "required" "send the PDF in the field pdf"]
            Just (Left e) -> [e]
            Just (Right _) -> []
          errs = upload.errors <> either id (const []) checked <> pdfErrors
          done o = pure (o, upload.fields)
      case (errs, received, checked) of
        (_ : _, _, _) -> do
          discard
          let big = any (\e -> e.field == "pdf" && e.code == "too_large") errs
          done (Failed Failure {status = if big then 413 else 400, retryAfter = Nothing, errors = errs, existing = Nothing})
        ([], Just r, Right submission) -> do
          old <- StudyStore.findByHash config.db account.githubId r.sha256
          fits <- PdfIntake.fitsQuota config r
          case old of
            Just o -> do
              discard
              done (Failed Failure {status = 409, retryAfter = Nothing, errors = [FieldError "pdf" "duplicate" "this account already sent this file"], existing = Just o})
            Nothing
              | not fits -> do
                  discard
                  env.logger "Marola.Studies" Warning "study store quota reached"
                  done (failure 507 Nothing "pdf" "quota_exceeded" "the study store is full; try again later and tell the board")
              | dry -> done (DryRun r submission)
              | otherwise -> do
                  inserted <- StudyStore.insertStudy config.db now account r.sha256 submission
                  case inserted of
                    Nothing -> do
                      -- Lost a race with the same upload: the other request owns the row.
                      discard
                      done (failure 409 Nothing "pdf" "duplicate" "this account already sent this file")
                    Just record -> do
                      PdfIntake.commit config r
                      -- Ids only: the title, the abstract and the file name are the author's.
                      env.logger "Marola.Studies" Information ("study stored " <> record.id <> " account " <> tshow account.githubId)
                      done (Created record)
        _ -> error "unreachable: no errors means a file and a submission"

failureResponse :: Failure -> Response
failureResponse f =
  let st = toEnum f.status
      extra = maybe [] (\v -> [("Retry-After", TE.encodeUtf8 v)]) f.retryAfter
   in case f.existing of
        Just old ->
          json
            st
            "no-store"
            ( JObject
                [ ("errors", JArray [JObject [("field", JString "pdf"), ("code", JString "duplicate"), ("message", JString "this account already sent this file")]])
                , ("id", JString old)
                , ("url", JString (urlOf old))
                ]
            )
            extra
        Nothing -> json st "no-store" (errorsJson f.errors) extra

bearer :: Request -> Text
bearer req =
  let h = header req hAuthorization
   in if T.toLower (T.take 7 h) == "bearer " then T.strip (T.drop 7 h) else ""

-- | @POST /api/v1/studies@.
submit :: Env -> Request -> IO Response
submit env req = do
  let key = bearer req
  account <- StudyStore.verifyKey env.config.db key
  case account of
    Nothing -> pure (failJson status401 "request" "unauthorized" "send a valid API key as: Authorization: Bearer msk_..." [("WWW-Authenticate", "Bearer")])
    Just a -> do
      (outcome, _) <- intake env req a (StudyStore.hashKey key) Set.empty (const True)
      pure $ case outcome of
        Failed f -> failureResponse f
        DryRun r s ->
          json
            status200
            "no-store"
            ( JObject
                [ ("dry_run", JBool True)
                , ("ok", JBool True)
                , ("sha256", JString r.sha256)
                , ("size_bytes", JInt r.size)
                , ("status", JString "public")
                , ("review", JString "not reviewed")
                , ("notice", JString notice)
                , ("submission", JObject (submissionJson s))
                ]
            )
            []
        Created record -> json status201 "no-store" (receiptJson record) []

-- ---- GET -----------------------------------------------------------------------------------------

-- | Int32.TryParse: white space around, an optional sign, digits.
parseInt :: Text -> Maybe Int
parseInt t =
  let s = T.strip t
      (sign, digits) = case T.uncons s of
        Just ('+', r) -> (1, r)
        Just ('-', r) -> (-1, r)
        _ -> (1, s)
   in if not (T.null digits) && T.all isDigit digits && T.length digits <= 10
        then let n = sign * read (T.unpack digits) :: Integer in if abs n <= 2147483647 then Just (fromInteger n) else Nothing
        else Nothing

-- | @GET /api/v1/studies@.
list :: Env -> Request -> IO Response
list env req = do
  let q = queryText req
      opt n parse values = case q n of
        "" -> (Nothing, [])
        v -> case parse v of
          Just x -> (Just x, [])
          Nothing -> (Nothing, [FieldError (TE.decodeUtf8 n) "invalid" (TE.decodeUtf8 n <> " must be one of: " <> T.intercalate ", " values)])
      (ar, e1) = opt "area" parseArea areaValues
      (tp, e2) = opt "topic" parseTopic topicValues
      (before, e3) = case q "before" of
        "" -> (Nothing, [])
        b | validId b -> (Just b, [])
        _ -> (Nothing, [FieldError "before" "invalid" "before must be a study id"])
      (limit, e4) = case q "limit" of
        "" -> (listDefault, [])
        l -> case parseInt l of
          Just n | n >= 1 && n <= listMax -> (n, [])
          _ -> (listDefault, [FieldError "limit" "invalid" ("limit must be 1 to " <> tshow listMax)])
      errs = e1 <> e2 <> e3 <> e4
  if not (null errs)
    then pure (json status400 "no-store" (errorsJson errs) [])
    else do
      studies <- StudyStore.listStudies env.config.db ar tp before limit
      pure $
        json
          status200
          "public, max-age=60"
          ( JObject
              [ ("notice", JString notice)
              , ("studies", JArray (map recordJson studies))
              , ("next_before", if length studies == limit && not (null studies) then JString (last studies).id else JNull)
              ]
          )
          []

notFound :: Response
notFound = failJson status404 "id" "not_found" "no study with this id" []

-- | @GET /api/v1/studies/<id>@.
one :: Env -> Text -> IO Response
one env i = do
  r <- if validId i then StudyStore.getStudy env.config.db i else pure Nothing
  pure $ maybe notFound (\x -> json status200 "public, max-age=60" (recordJson x) []) r

-- | The file of a public study. @sandbox@ and @default-src 'none'@ replace the page's CSP: whatever
-- a PDF viewer would run runs with no origin and no network.
pdf :: Env -> Text -> IO Response
pdf env file = do
  let i = fromMaybe "" (T.stripSuffix ".pdf" file)
  r <- if validId i then StudyStore.getStudy env.config.db i else pure Nothing
  case r of
    Just x | x.status == Public -> do
      let path = PdfIntake.pathOf env.config x.sha256
      there <- doesFileExist path
      if there
        then
          pure $
            responseFile
              status200
              [ (hContentType, "application/pdf")
              , ("Content-Disposition", "inline; filename=\"" <> TE.encodeUtf8 i <> ".pdf\"")
              , ("X-Content-Type-Options", "nosniff")
              , ("Content-Security-Policy", "sandbox; default-src 'none'")
              , (hCacheControl, "public, max-age=3600")
              ]
              path
              Nothing
        else do
          env.logger "Marola.Studies" Error ("study file missing " <> i)
          pure notFound
    _ -> pure notFound

-- ---- skill.md ------------------------------------------------------------------------------------

skill :: Text
skill =
  let levels = T.intercalate "\n" ["- `" <> v <> "`: " <> levelMeaning l | v <- levelValues, Just l <- [parseLevel v]]
      j = T.intercalate ", "
   in T.unlines
        [ "# Submit a study to marola"
        , ""
        , "marola publishes studies by anyone with a GitHub account that is at least 7 days old. A study is public at once"
        , "and is labelled \"not reviewed, not medical advice\". The board can hide a study later; it then keeps its hash,"
        , "its date and a reason. Only open licences are accepted, because marola hosts the file."
        , ""
        , "## Get a key"
        , ""
        , "Sign in with GitHub on marola.dev and make an API key (`msk_...`). The key is shown once. An account has at most 3 active keys."
        , "Send it as `Authorization: Bearer $MAROLA_KEY`. Never put a key in a repository or a log."
        , ""
        , "## Endpoint"
        , ""
        , "`POST https://marola.dev/api/v1/studies` with `multipart/form-data`. Add `?dry_run=1` to check everything"
        , "(the file and the limits too) with nothing stored. The same API as an OpenAPI 3.1 document: `https://marola.dev/api/v1/openapi.json`."
        , ""
        , "| field | rule |"
        , "|---|---|"
        , "| `title` | 5 to 200 characters, one line |"
        , "| `authors` | 1 to 20 lines. One author per line: `Name` or `Name | 0000-0002-1825-0097` (an ORCID iD with its check digit). A name has 2 to 120 characters |"
        , "| `abstract` | 100 to 4000 characters |"
        , "| `area` | " <> j areaValues <> " |"
        , "| `topic` | " <> j topicValues <> " |"
        , "| `sources` | 0 to 10 https links, one per line |"
        , "| `repository` | optional https link |"
        , "| `licence` | " <> j licenceValues <> ". Default `CC-BY-4.0` |"
        , "| `rights` | `true`: you have the right to publish this file under that licence |"
        , "| `ai_models` | optional, up to 300 characters |"
        , "| `ai_contribution` | one of the levels below |"
        , "| `ai_process` | up to 1500 characters. Required unless `ai_contribution` is `none` |"
        , "| `pdf` | the file: a PDF of at most 20 MB |"
        , ""
        , "Each field appears once. Text is UTF-8. Control characters other than newline and tab are removed."
        , ""
        , "## AI contribution levels"
        , ""
        , levels
        , ""
        , "## The PDF"
        , ""
        , "It must start with `%PDF-` and end with `startxref` and `%%EOF`. marola refuses a file that has one of the names"
        , "`/Launch`, `/JavaScript`, `/JS`, `/EmbeddedFile` (also written with `#xx` escapes) or an `/OpenAction` whose value is"
        , "an action. Export the PDF again without scripts, attachments or launch actions."
        , ""
        , "## Examples"
        , ""
        , "```"
        , "curl -sS -H \"Authorization: Bearer $MAROLA_KEY\" \"https://marola.dev/api/v1/studies?dry_run=1\" \\"
        , "  -F title=\"Enterococcus at Leblon, 2025\" -F \"authors=Ana Silva | 0000-0002-1825-0097\" \\"
        , "  -F \"abstract=<abstract.txt\" -F area=rio -F topic=water-quality -F rights=true \\"
        , "  -F ai_contribution=none -F pdf=@study.pdf"
        , "```"
        , ""
        , "Drop `?dry_run=1` to publish. Success is `201` with `id`, `url`, `pdf_url`, `sha256`, `received_utc`, `status` and `record`."
        , ""
        , "```"
        , "curl -sS \"https://marola.dev/api/v1/studies?area=rio&topic=water-quality&limit=20\""
        , "curl -sS \"https://marola.dev/api/v1/studies/<id>\""
        , "```"
        , ""
        , "## Errors"
        , ""
        , "`400` returns `{\"errors\":[{\"field\",\"code\",\"message\"}]}` with every error at once. The codes are"
        , "`required`, `too_short`, `too_long`, `too_many`, `invalid`, `unknown_value`, `bad_name`, `bad_orcid`, `bad_link`,"
        , "`must_be_true`, `invalid_utf8`, `duplicate_field`, `unknown_field`, `too_many_parts`, `malformed_multipart`,"
        , "and for the file `not_pdf`, `truncated`, `active_content`, `pdf_encrypted`, `pdf_unscannable`."
        , "`401` bad or missing key. `403` the account is under 7 days old. `409` this account sent this file already (the answer has the old `id`)."
        , "`413` the file or the request is too large. `415` not multipart. `429` too many requests: one real submission per account every 10 minutes and 10 a day,"
        , "30 requests a minute per key (a dry run counts a third); read `Retry-After`. `507` the study store is full."
        ]

skillResponse :: Response
skillResponse =
  responseLBS
    status200
    [(hContentType, "text/plain; charset=utf-8"), (hCacheControl, "public, max-age=300")]
    (BL.fromStrict (TE.encodeUtf8 skill))

-- | The API routes, by method and path; 'Nothing' for any other request.
route :: Env -> Request -> Text -> Maybe (IO Response)
route env req path = case (requestMethod req, T.stripPrefix apiPath path) of
  ("POST", Just "") -> Just (submit env req)
  ("GET", Just "") -> Just (list env req)
  ("HEAD", Just "") -> Just (list env req)
  ("GET", Just rest) | Just i <- oneSegment rest -> Just (one env i)
  ("HEAD", Just rest) | Just i <- oneSegment rest -> Just (one env i)
  (m, Nothing) | path == "/api/v1/skill.md" && (m == "GET" || m == "HEAD") -> Just (pure skillResponse)
  _ -> Nothing
  where
    oneSegment r = case T.stripPrefix "/" r of
      Just i | not (T.null i) && not ("/" `T.isInfixOf` i) -> Just i
      _ -> Nothing
