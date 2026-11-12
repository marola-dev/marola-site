-- | A study submitted by a scientist: the types, the validation of the form fields and the JSON the
-- API answers with. A port of app/Shared/Study.fs; the PDF is checked by the server.
module Marola.Study
  ( Area (..)
  , Topic (..)
  , Licence (..)
  , AiContribution (..)
  , Status (..)
  , Author (..)
  , Submission (..)
  , Record (..)
  , FieldError (..)
  , areaName
  , topicName
  , licenceName
  , levelName
  , statusName
  , parseArea
  , parseTopic
  , parseLicence
  , parseLevel
  , parseStatus
  , areaValues
  , topicValues
  , licenceValues
  , levelValues
  , allLevels
  , allAreas
  , allTopics
  , levelMeaning
  , titleMin
  , titleMax
  , authorsMax
  , authorNameMin
  , authorNameMax
  , abstractMin
  , abstractMax
  , sourcesMax
  , linkMax
  , aiModelsMax
  , aiProcessMax
  , cleanText
  , validOrcid
  , httpsLink
  , validate
  , urlOf
  , pdfUrlOf
  , notice
  , errorsJson
  , submissionJson
  , recordJson
  , receiptJson
  , idAlphabet
  , validId
  , validSha256
  )
where

import Data.Char (isDigit, ord)
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Html (safeHref)
import Marola.Json
import Marola.Utf16 qualified as U

data Area = Rio | Floripa | Salvador | OtherArea deriving (Eq, Show, Enum, Bounded)

data Topic = WaterQuality | Waves | WindTopic | TrailsTopic | Ecology | Safety | DataTopic | OtherTopic
  deriving (Eq, Show, Enum, Bounded)

-- | Only open licences: marola hosts and serves the file.
data Licence = CcBy40 | CcBySa40 | Cc01 deriving (Eq, Show, Enum, Bounded)

-- | How much of the work an AI system did. The author states it; marola does not check it.
data AiContribution = NoAi | LanguageEditing | AnalysisAssistance | Drafting | Substantial | Autonomous
  deriving (Eq, Show, Enum, Bounded)

data Status = Public | Hidden deriving (Eq, Show)

data Author = Author {name :: Text, orcid :: Maybe Text} deriving (Eq, Show)

data Submission = Submission
  { title :: Text
  , authors :: [Author]
  , abstract :: Text
  , area :: Area
  , topic :: Topic
  , sources :: [Text]
  , repository :: Maybe Text
  , licence :: Licence
  , aiModels :: Text
  , aiContribution :: AiContribution
  , aiProcess :: Text
  }
  deriving (Eq, Show)

data Record = Record
  { id :: Text
  , receivedUtc :: Text
  , sha256 :: Text
  , submission :: Submission
  , authorLogin :: Text
  , authorGithubId :: Int64
  , status :: Status
  , hiddenReason :: Maybe Text
  , hiddenUtc :: Maybe Text
  }
  deriving (Eq, Show)

data FieldError = FieldError {field :: Text, code :: Text, message :: Text} deriving (Eq, Show)

-- The wire names. One table per set, so `parse` and `name` cannot drift apart.
areaNames :: [(Area, Text)]
areaNames = [(Rio, "rio"), (Floripa, "floripa"), (Salvador, "salvador"), (OtherArea, "other")]

topicNames :: [(Topic, Text)]
topicNames =
  [ (WaterQuality, "water-quality")
  , (Waves, "waves")
  , (WindTopic, "wind")
  , (TrailsTopic, "trails")
  , (Ecology, "ecology")
  , (Safety, "safety")
  , (DataTopic, "data")
  , (OtherTopic, "other")
  ]

licenceNames :: [(Licence, Text)]
licenceNames = [(CcBy40, "CC-BY-4.0"), (CcBySa40, "CC-BY-SA-4.0"), (Cc01, "CC0-1.0")]

levelNames :: [(AiContribution, Text)]
levelNames =
  [ (NoAi, "none")
  , (LanguageEditing, "language-editing")
  , (AnalysisAssistance, "analysis-assistance")
  , (Drafting, "drafting")
  , (Substantial, "substantial")
  , (Autonomous, "autonomous")
  ]

statusNames :: [(Status, Text)]
statusNames = [(Public, "public"), (Hidden, "hidden")]

nameOf :: (Eq a) => [(a, Text)] -> a -> Text
nameOf table v = fromMaybe "" (lookup v table)

parseWith :: [(a, Text)] -> Text -> Maybe a
parseWith table t = fst <$> safeHead (filter ((== t) . snd) table)
  where
    safeHead (x : _) = Just x
    safeHead [] = Nothing

areaName :: Area -> Text
areaName = nameOf areaNames
topicName :: Topic -> Text
topicName = nameOf topicNames
licenceName :: Licence -> Text
licenceName = nameOf licenceNames
levelName :: AiContribution -> Text
levelName = nameOf levelNames
statusName :: Status -> Text
statusName = nameOf statusNames

parseArea :: Text -> Maybe Area
parseArea = parseWith areaNames
parseTopic :: Text -> Maybe Topic
parseTopic = parseWith topicNames
parseLicence :: Text -> Maybe Licence
parseLicence = parseWith licenceNames
parseLevel :: Text -> Maybe AiContribution
parseLevel = parseWith levelNames
parseStatus :: Text -> Maybe Status
parseStatus = parseWith statusNames

areaValues, topicValues, licenceValues, levelValues :: [Text]
areaValues = map snd areaNames
topicValues = map snd topicNames
licenceValues = map snd licenceNames
levelValues = map snd levelNames

allLevels :: [AiContribution]
allLevels = map fst levelNames
allAreas :: [Area]
allAreas = map fst areaNames
allTopics :: [Topic]
allTopics = map fst topicNames

-- | What each level means, for the API guide and the pages.
levelMeaning :: AiContribution -> Text
levelMeaning = \case
  NoAi -> "No AI system took part."
  LanguageEditing -> "An AI system fixed or translated the text. The ideas and the results are the authors'."
  AnalysisAssistance -> "An AI system helped with code, data or statistics. The authors checked the output."
  Drafting -> "An AI system wrote parts of the text. The authors planned, edited and checked it."
  Substantial -> "An AI system did most of the analysis or the writing. The authors directed and checked it."
  Autonomous -> "An AI system did the work with no human step between the question and the file."

titleMin, titleMax, authorsMax, authorNameMin, authorNameMax, abstractMin, abstractMax :: Int
titleMin = 5
titleMax = 200
authorsMax = 20
authorNameMin = 2
authorNameMax = 120
abstractMin = 100
abstractMax = 4000

sourcesMax, linkMax, aiModelsMax, aiProcessMax :: Int
sourcesMax = 10
linkMax = 500
aiModelsMax = 300
aiProcessMax = 1500

tshow :: Int -> Text
tshow = T.pack . show

-- | Control characters other than newline and tab are dropped; a lone carriage return goes with them.
cleanText :: Text -> Text
cleanText = T.strip . T.filter keep
  where
    keep c = not (c < ' ' && c /= '\n' && c /= '\t') && not (c >= '\x7f' && c <= '\x9f')

-- | ISO 7064 MOD 11-2 check character of the first 15 digits of an ORCID iD.
orcidCheck :: String -> Char
orcidCheck digits =
  let total = foldl (\acc c -> (acc + (ord c - ord '0')) * 2) 0 digits
   in case (12 - total `mod` 11) `mod` 11 of
        10 -> 'X'
        n -> toEnum (ord '0' + n)

-- | @0000-0002-1825-0097@: the shape, then the check character.
validOrcid :: Text -> Bool
validOrcid t =
  T.length t == 19
    && and (zipWith shape [0 :: Int ..] s)
    && orcidCheck (filter (/= '-') (take 18 s)) == s !! 18
  where
    s = T.unpack t
    shape i c
      | i `elem` [4, 9, 14] = c == '-'
      | i == 18 = isDigit c || c == 'X'
      | otherwise = isDigit c

err :: Text -> Text -> Text -> FieldError
err = FieldError

hasLineBreak :: Text -> Bool
hasLineBreak s = T.any (\c -> c == '\n' || c == '\t') s

-- | A single-line text field with a length range.
line :: Text -> Int -> Int -> Text -> Either FieldError Text
line f lo hi value
  | T.null value && lo > 0 = Left (err f "required" (f <> " is required"))
  | hasLineBreak value = Left (err f "invalid" (f <> " must be one line of text"))
  | U.len value < lo = Left (err f "too_short" (f <> " needs at least " <> tshow lo <> " characters"))
  | U.len value > hi = Left (err f "too_long" (f <> " takes at most " <> tshow hi <> " characters"))
  | otherwise = Right value

-- | An https link that a page may print in an @href@.
httpsLink :: Text -> Maybe Text
httpsLink url = case safeHref url of
  Just cleaned
    | U.len cleaned > 8 && U.len cleaned <= linkMax && "https://" `T.isPrefixOf` T.toLower cleaned -> Just cleaned
  _ -> Nothing

nonEmptyLines :: Text -> [Text]
nonEmptyLines = filter (not . T.null) . map T.strip . T.splitOn "\n"

parseAuthor :: Int -> Text -> Either FieldError Author
parseAuthor index txt =
  let (nm, orc) = case T.breakOn "|" txt of
        (_, "") -> (txt, Nothing)
        (a, b) -> (T.strip a, Just (T.strip (T.drop 1 b)))
      wher = "authors line " <> tshow (index + 1)
   in if U.len nm < authorNameMin || U.len nm > authorNameMax
        then
          Left
            ( err
                "authors"
                "bad_name"
                (wher <> ": the name needs " <> tshow authorNameMin <> " to " <> tshow authorNameMax <> " characters")
            )
        else case orc of
          Nothing -> Right (Author nm Nothing)
          Just o
            | not (validOrcid o) ->
                Left (err "authors" "bad_orcid" (wher <> ": the ORCID iD is not valid or its check digit is wrong"))
            | otherwise -> Right (Author nm (Just o))

collect :: [Either FieldError a] -> Either [FieldError] [a]
collect results = case [e | Left e <- results] of
  [] -> Right [v | Right v <- results]
  es -> Left es

enumField :: Text -> [Text] -> (Text -> Maybe a) -> Text -> Either FieldError a
enumField f values parse raw
  | T.null raw = Left (err f "required" (f <> " is required"))
  | otherwise = case parse raw of
      Just v -> Right v
      Nothing -> Left (err f "unknown_value" (f <> " must be one of: " <> T.intercalate ", " values))

-- | Checks every text field at once. @get@ returns the raw text of a form field, or 'Nothing' when
-- the field is missing. The PDF is not here: the server checks it and adds its own errors.
validate :: (Text -> Maybe Text) -> Either [FieldError] Submission
validate get =
  let text n = maybe "" cleanText (get n)
      title' = line "title" titleMin titleMax (text "title")
      authors' = case nonEmptyLines (text "authors") of
        [] -> Left [err "authors" "required" "authors needs at least one author"]
        ls
          | length ls > authorsMax -> Left [err "authors" "too_many" ("authors takes at most " <> tshow authorsMax <> " authors")]
          | otherwise -> collect (zipWith parseAuthor [0 ..] ls)
      abstract' =
        let v = text "abstract"
         in if
              | T.null v -> Left (err "abstract" "required" "abstract is required")
              | U.len v < abstractMin -> Left (err "abstract" "too_short" ("abstract needs at least " <> tshow abstractMin <> " characters"))
              | U.len v > abstractMax -> Left (err "abstract" "too_long" ("abstract takes at most " <> tshow abstractMax <> " characters"))
              | otherwise -> Right v
      area' = enumField "area" areaValues parseArea (text "area")
      topic' = enumField "topic" topicValues parseTopic (text "topic")
      sources' =
        let ls = nonEmptyLines (text "sources")
         in if length ls > sourcesMax
              then Left [err "sources" "too_many" ("sources takes at most " <> tshow sourcesMax <> " links")]
              else
                collect
                  [ maybe (Left (err "sources" "bad_link" ("sources line " <> tshow i <> " is not an https link"))) Right (httpsLink l)
                  | (i, l) <- zip [1 :: Int ..] ls
                  ]
      repository' = case text "repository" of
        "" -> Right Nothing
        url -> maybe (Left (err "repository" "bad_link" "repository must be an https link")) (Right . Just) (httpsLink url)
      licence' = case text "licence" of
        "" -> Right CcBy40
        raw -> enumField "licence" licenceValues parseLicence raw
      rights' = case text "rights" of
        r
          | r `elem` ["true", "1"] -> Right ()
          | otherwise -> Left (err "rights" "must_be_true" "rights must be true: you may publish this file under the licence you chose")
      aiModels' = line "ai_models" 0 aiModelsMax (text "ai_models")
      level' = enumField "ai_contribution" levelValues parseLevel (text "ai_contribution")
      aiProcess' =
        let v = text "ai_process"
         in case level' of
              Right l | l /= NoAi && T.null v -> Left (err "ai_process" "required" "ai_process is required when an AI system took part")
              _
                | U.len v > aiProcessMax -> Left (err "ai_process" "too_long" ("ai_process takes at most " <> tshow aiProcessMax <> " characters"))
                | otherwise -> Right v
      single = either pure (const [])
      many = either Prelude.id (const [])
      errors =
        single title'
          <> many authors'
          <> single abstract'
          <> single area'
          <> single topic'
          <> many sources'
          <> single repository'
          <> single licence'
          <> single rights'
          <> single aiModels'
          <> single level'
          <> single aiProcess'
   in case (title', authors', abstract', area', topic', sources', repository', licence', rights', aiModels', level', aiProcess') of
        (Right t, Right au, Right ab, Right ar, Right tp, Right so, Right re, Right li, Right (), Right am, Right lv, Right ap)
          | null errors ->
              Right (Submission t au ab ar tp so re li am lv ap)
        _ -> Left errors

-- ---- JSON ---------------------------------------------------------------------------------------

optString :: Maybe Text -> Json
optString = maybe JNull JString

urlOf, pdfUrlOf :: Text -> Text
urlOf i = "/studies/" <> i
pdfUrlOf i = "/studies/" <> i <> ".pdf"

-- | The notice every public view carries, in the JSON too.
notice :: Text
notice = "Not reviewed. Not medical advice."

errorsJson :: [FieldError] -> Json
errorsJson es =
  JObject
    [ ("errors", JArray [JObject [("field", JString e.field), ("code", JString e.code), ("message", JString e.message)] | e <- es])
    ]

submissionJson :: Submission -> [(Text, Json)]
submissionJson s =
  [ ("title", JString s.title)
  , ("authors", JArray [JObject [("name", JString a.name), ("orcid", optString a.orcid)] | a <- s.authors])
  , ("abstract", JString s.abstract)
  , ("area", JString (areaName s.area))
  , ("topic", JString (topicName s.topic))
  , ("sources", JArray (map JString s.sources))
  , ("repository", optString s.repository)
  , ("licence", JString (licenceName s.licence))
  , ("ai_models", JString s.aiModels)
  , ("ai_contribution", JString (levelName s.aiContribution))
  , ("ai_process", JString s.aiProcess)
  ]

-- | The public record. A hidden study is a tombstone: id, hash, date, status and reason, never the
-- text the author wrote and never a link to the file.
recordJson :: Record -> Json
recordJson r = case r.status of
  Hidden ->
    JObject
      [ ("id", JString r.id)
      , ("sha256", JString r.sha256)
      , ("received_utc", JString r.receivedUtc)
      , ("status", JString (statusName r.status))
      , ("reason", optString r.hiddenReason)
      , ("hidden_utc", optString r.hiddenUtc)
      , ("notice", JString notice)
      ]
  Public ->
    JObject
      ( [ ("id", JString r.id)
        , ("sha256", JString r.sha256)
        , ("received_utc", JString r.receivedUtc)
        , ("status", JString (statusName r.status))
        , ("review", JString "not reviewed")
        , ("notice", JString notice)
        ]
          <> submissionJson r.submission
          <> [ ("author_login", JString r.authorLogin)
             , ("author_github_id", JInt r.authorGithubId)
             , ("url", JString (urlOf r.id))
             , ("pdf_url", JString (pdfUrlOf r.id))
             ]
      )

-- | The answer to a successful @POST /api/v1/studies@.
receiptJson :: Record -> Json
receiptJson r =
  JObject
    [ ("id", JString r.id)
    , ("url", JString (urlOf r.id))
    , ("pdf_url", JString (pdfUrlOf r.id))
    , ("sha256", JString r.sha256)
    , ("received_utc", JString r.receivedUtc)
    , ("status", JString (statusName r.status))
    , ("record", recordJson r)
    ]

-- ---- ids -----------------------------------------------------------------------------------------

idAlphabet :: Text
idAlphabet = "abcdefghijklmnopqrstuvwxyz234567"

-- | A study id: 10 characters of lower-case base32. The only text that reaches a path or a query.
validId :: Text -> Bool
validId i = T.length i == 10 && T.all (`T.elem` idAlphabet) i

validSha256 :: Text -> Bool
validSha256 h = T.length h == 64 && T.all (\c -> isDigit c || (c >= 'a' && c <= 'f')) h
