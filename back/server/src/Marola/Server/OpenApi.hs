-- | @GET /api/v1/openapi.json@: the OpenAPI 3.1 description of @/api/v1@, built from one value. Every
-- number comes from "Marola.Study", "Marola.Server.StudyApi" or "Marola.Server.PdfIntake", so the
-- document cannot say something the validation does not do.
module Marola.Server.OpenApi (path, errorCodes, document, text, response) where

import Data.ByteString.Lazy qualified as BL
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Json
import Marola.Server.Messages qualified as Messages
import Marola.Server.PdfIntake qualified as PdfIntake
import Marola.Server.StudyApi qualified as StudyApi
import Marola.Study
import Network.HTTP.Types (hCacheControl, hContentType, status200)
import Network.Wai (Response, responseLBS)

path :: Text
path = "/api/v1/openapi.json"

s :: Text -> Json
s = JString

n :: Int -> Json
n = JInt . fromIntegral

strings :: [Text] -> Json
strings = JArray . map JString

ref' :: Text -> Json
ref' name = JObject [("$ref", s ("#/components/schemas/" <> name))]

ofType :: Text -> Text -> [(Text, Json)]
ofType kind description = [("type", s kind), ("description", s description)]

textField :: Text -> Json
textField = JObject . ofType "string"

bounded :: Int -> Int -> Text -> Json
bounded lo hi d = JObject (ofType "string" d <> [("minLength", n lo), ("maxLength", n hi)])

choice :: [Text] -> Text -> Json
choice values d = JObject (ofType "string" d <> [("enum", strings values)])

tshow :: (Show a) => a -> Text
tshow = T.pack . show

-- | The codes an API client can see. @csrf@ belongs to the web form only; @not_found@ is the 404 of
-- the GET routes.
errorCodes :: [Text]
errorCodes = filter (/= "csrf") Messages.codes <> ["not_found"]

keyedRate :: Int
keyedRate = StudyApi.perKeyUnits `div` StudyApi.realCost

withSchema :: Json -> (Text, Json)
withSchema schema = ("content", JObject [("application/json", JObject [("schema", schema)])])

reply :: Text -> [(Text, Json)] -> Json
reply d extra = JObject (("description", s d) : extra)

replyWith :: Text -> Json -> Json
replyWith d schema = reply d [withSchema schema]

retryAfter :: Text -> (Text, Json)
retryAfter what =
  ("headers", JObject [("Retry-After", JObject [("description", s what), ("schema", JObject [("type", s "integer")])])])

errors :: Text -> Json
errors d = replyWith d (ref' "ErrorBody")

errorsWith :: Text -> [(Text, Json)] -> Json
errorsWith d extra = reply d (withSchema (ref' "ErrorBody") : extra)

studySchema :: Text -> [Text] -> [(Text, Json)] -> (Text, Json)
studySchema name required props =
  (name, JObject [("type", s "object"), ("required", strings required), ("properties", JObject props)])

nullable :: Text -> Text -> Json
nullable kind d = JObject [("type", JArray [s kind, s "null"]), ("description", s d)]

submissionProps :: [(Text, Json)]
submissionProps =
  [ ("title", textField "The title.")
  , ( "authors"
    , JObject
        [ ("type", s "array")
        , ( "items"
          , JObject
              [ ("type", s "object")
              , ("required", strings ["name", "orcid"])
              , ("properties", JObject [("name", textField "The author's name."), ("orcid", nullable "string" "The ORCID iD, or null.")])
              ]
          )
        ]
    )
  , ("abstract", textField "The abstract.")
  , ("area", choice areaValues "The area the study is about.")
  , ("topic", choice topicValues "The topic.")
  , ("sources", JObject [("type", s "array"), ("items", JObject [("type", s "string"), ("format", s "uri")])])
  , ("repository", nullable "string" "An https link to the code or data, or null.")
  , ("licence", choice licenceValues "The licence of the file.")
  , ("ai_models", textField "The AI systems used, as the author wrote it.")
  , ("ai_contribution", choice levelValues "How much of the work an AI system did, as the author states it.")
  , ("ai_process", textField "How the AI system was used.")
  ]

statusValues :: [Text]
statusValues = map statusName [Public, Hidden]

idPattern :: Text
idPattern = "^[" <> idAlphabet <> "]{10}$"

recordProps :: [(Text, Json)]
recordProps =
  [ ("id", JObject (ofType "string" "The study id." <> [("pattern", s idPattern)]))
  , ("sha256", JObject (ofType "string" "The SHA-256 of the file, in lower-case hex." <> [("pattern", s "^[0-9a-f]{64}$")]))
  , ("received_utc", textField "When the server received the study (UTC, ISO 8601).")
  , ("status", choice statusValues "`hidden` is a tombstone: no text and no link, only the hash, the dates and the reason.")
  , ("review", textField "Always `not reviewed` for a public study.")
  , ("notice", textField notice)
  , ("reason", nullable "string" "Why the board or the author hid the study (a tombstone only).")
  , ("hidden_utc", nullable "string" "When it was hidden (a tombstone only).")
  ]
    <> submissionProps
    <> [ ("author_login", textField "The GitHub login of the author who sent the study.")
       , ("author_github_id", JObject (ofType "integer" "The GitHub id of that account."))
       , ("url", textField "The page of the study.")
       , ("pdf_url", textField "The file.")
       ]

schemas :: [(Text, Json)]
schemas =
  [ ( "ErrorBody"
    , JObject
        [ ("type", s "object")
        , ("required", strings ["errors"])
        , ( "properties"
          , JObject
              [ ( "errors"
                , JObject
                    [ ("type", s "array")
                    , ("items", ref' "Error")
                    , ("description", s "Every error at once: a client can fix them in one pass.")
                    ]
                )
              ]
          )
        ]
    )
  , ( "Error"
    , JObject
        [ ("type", s "object")
        , ("required", strings ["field", "code", "message"])
        , ( "properties"
          , JObject
              [ ("field", textField "The form field, or `request` when the problem is the request as a whole.")
              , ("code", choice errorCodes "A stable machine code. Match on this, not on `message`.")
              , ("message", textField "A plain English sentence for a person. It can change.")
              ]
          )
        ]
    )
  , ( "Duplicate"
    , JObject
        [ ( "allOf"
          , JArray
              [ ref' "ErrorBody"
              , JObject
                  [ ("type", s "object")
                  , ("required", strings ["id", "url"])
                  , ("properties", JObject [("id", textField "The id of the study this account already sent."), ("url", textField "Its page.")])
                  ]
              ]
          )
        ]
    )
  , studySchema "Submission" ["title", "authors", "abstract"] submissionProps
  , studySchema "Record" ["id", "sha256", "received_utc", "status", "notice"] recordProps
  , studySchema
      "Receipt"
      ["id", "url", "pdf_url", "sha256", "received_utc", "status", "record"]
      [ ("id", textField "The study id.")
      , ("url", textField "The page of the study.")
      , ("pdf_url", textField "The file.")
      , ("sha256", textField "The SHA-256 of the file.")
      , ("received_utc", textField "When the server received it.")
      , ("status", choice statusValues "Always `public` at first.")
      , ("record", ref' "Record")
      ]
  , studySchema
      "DryRun"
      ["dry_run", "ok", "sha256", "size_bytes", "status", "review", "notice", "submission"]
      [ ("dry_run", JObject (ofType "boolean" "Always true."))
      , ("ok", JObject (ofType "boolean" "Always true: every check passed and nothing was stored."))
      , ("sha256", textField "The SHA-256 of the file.")
      , ("size_bytes", JObject (ofType "integer" "The size of the file."))
      , ("status", textField "`public`: what the status would be.")
      , ("review", textField "`not reviewed`.")
      , ("notice", textField notice)
      , ("submission", ref' "Submission")
      ]
  , studySchema
      "StudyList"
      ["notice", "studies", "next_before"]
      [ ("notice", textField notice)
      , ("studies", JObject [("type", s "array"), ("items", ref' "Record")])
      , ("next_before", nullable "string" "Pass it as `before` to get the next page. Null on the last page.")
      ]
  ]

mb :: Int64 -> Text
mb bytes = tshow (bytes `div` 1024 `div` 1024)

submitSchema :: Json
submitSchema =
  JObject
    [ ("type", s "object")
    , ("required", strings ["title", "authors", "abstract", "area", "topic", "rights", "ai_contribution", "pdf"])
    , ( "description"
      , s
          ( "Each field appears once; an unknown or repeated field is an error. Text is UTF-8, and control characters other than newline and tab are removed before the lengths count (in UTF-16 code units). The body has at most "
              <> tshow StudyApi.maxParts
              <> " parts, a text field at most "
              <> tshow StudyApi.maxFieldBytes
              <> " bytes, and the whole request at most "
              <> mb StudyApi.uploadLimit
              <> " MB."
          )
      )
    , ("x-max-parts", n StudyApi.maxParts)
    , ("x-max-field-bytes", n StudyApi.maxFieldBytes)
    , ("x-max-request-bytes", JInt StudyApi.uploadLimit)
    , ( "properties"
      , JObject
          [ ("title", bounded titleMin titleMax "One line.")
          , ( "authors"
            , JObject
                ( ofType
                    "string"
                    ( "One author per line, "
                        <> tshow authorsMax
                        <> " lines at most: `Name` or `Name | 0000-0002-1825-0097` (an ORCID iD with its check digit). A name has "
                        <> tshow authorNameMin
                        <> " to "
                        <> tshow authorNameMax
                        <> " characters."
                    )
                    <> [("x-max-lines", n authorsMax), ("x-name-min-length", n authorNameMin), ("x-name-max-length", n authorNameMax)]
                )
            )
          , ("abstract", bounded abstractMin abstractMax "The abstract.")
          , ("area", choice areaValues "The area the study is about.")
          , ("topic", choice topicValues "The topic.")
          , ( "sources"
            , JObject
                ( ofType "string" ("0 to " <> tshow sourcesMax <> " https links, one per line, each at most " <> tshow linkMax <> " characters.")
                    <> [("x-max-lines", n sourcesMax), ("x-max-line-length", n linkMax)]
                )
            )
          , ("repository", JObject (ofType "string" ("Optional https link of at most " <> tshow linkMax <> " characters.") <> [("maxLength", n linkMax)]))
          , ( "licence"
            , JObject (ofType "string" "Open licences only, because marola hosts the file." <> [("enum", strings licenceValues), ("default", s (licenceName CcBy40))])
            )
          , ("rights", choice ["true", "1"] "Must be `true`: you may publish this file under the licence you chose.")
          , ("ai_models", JObject (ofType "string" "Optional." <> [("maxLength", n aiModelsMax)]))
          , ( "ai_contribution"
            , choice
                levelValues
                ("How much of the work an AI system did. " <> T.intercalate " " ["`" <> v <> "`: " <> levelMeaning l | v <- levelValues, Just l <- [parseLevel v]])
            )
          , ("ai_process", JObject (ofType "string" "Required unless `ai_contribution` is `none`." <> [("maxLength", n aiProcessMax)]))
          , ("pdf", JObject (ofType "string" ("The file: a PDF of at most " <> mb PdfIntake.maxBytes <> " MB.") <> [("format", s "binary"), ("x-max-bytes", JInt PdfIntake.maxBytes)]))
          ]
      )
    ]

idParameter :: Json
idParameter =
  JObject
    [ ("name", s "id")
    , ("in", s "path")
    , ("required", JBool True)
    , ("description", s "The study id: 10 characters of lower-case base32.")
    , ("schema", JObject [("type", s "string"), ("pattern", s idPattern)])
    ]

queryParameter :: Text -> Text -> Json -> Json
queryParameter name d schema =
  JObject [("name", s name), ("in", s "query"), ("required", JBool False), ("description", s d), ("schema", schema)]

post :: Json
post =
  JObject
    [ ("operationId", s "submitStudy")
    , ("summary", s "Submit a study")
    , ( "description"
      , s
          ( "Needs a key (`Authorization: Bearer msk_...`) of a GitHub account at least "
              <> tshow (floor (StudyApi.minAccountAge / 86400) :: Int)
              <> " days old. The study is public at once and labelled not reviewed. Limits: "
              <> tshow keyedRate
              <> " real requests a minute per key (a dry run counts "
              <> tshow StudyApi.dryCost
              <> " of "
              <> tshow StudyApi.realCost
              <> "), one real submission per account every "
              <> tshow (floor (StudyApi.gapBetween / 60) :: Int)
              <> " minutes and "
              <> tshow StudyApi.perDay
              <> " a day."
          )
      )
    , ("security", JArray [JObject [("bearerAuth", JArray [])]])
    , ( "parameters"
      , JArray
          [ queryParameter
              "dry_run"
              "`1` runs every check, including the file, and stores nothing. It gets the same refusals as a real submission."
              (JObject [("type", s "string"), ("enum", strings ["1"])])
          ]
      )
    , ("requestBody", JObject [("required", JBool True), ("content", JObject [("multipart/form-data", JObject [("schema", submitSchema)])])])
    , ( "responses"
      , JObject
          [ ("200", replyWith "Dry run: everything passed, nothing stored." (ref' "DryRun"))
          , ("201", replyWith "Stored and public." (ref' "Receipt"))
          , ("400", errors "One or more fields or the file are wrong, or the multipart body is malformed.")
          , ("401", errorsWith "Missing or wrong key. The response carries `WWW-Authenticate: Bearer`." [])
          , ("403", errors "The GitHub account is younger than the minimum age (`account_too_new`).")
          , ("409", replyWith "This account already sent this file. The body has the id of the old study." (ref' "Duplicate"))
          , ("413", errors "The file or the request is too large.")
          , ("415", errors "The body is not multipart/form-data.")
          , ("429", errorsWith "Too many requests. Read `Retry-After` (seconds)." [retryAfter "Seconds to wait."])
          , ("507", errors "The study store is full.")
          ]
      )
    ]

get :: Json
get =
  JObject
    [ ("operationId", s "listStudies")
    , ("summary", s "List public studies, newest first")
    , ( "parameters"
      , JArray
          [ queryParameter "area" "Only this area." (JObject [("type", s "string"), ("enum", strings areaValues)])
          , queryParameter "topic" "Only this topic." (JObject [("type", s "string"), ("enum", strings topicValues)])
          , queryParameter
              "before"
              "A study id: the page of studies older than it (`next_before` of the last page)."
              (JObject [("type", s "string"), ("pattern", s idPattern)])
          , queryParameter
              "limit"
              "Studies per page."
              (JObject [("type", s "integer"), ("minimum", n 1), ("maximum", n StudyApi.listMax), ("default", n StudyApi.listDefault)])
          ]
      )
    , ("responses", JObject [("200", replyWith "A page of studies." (ref' "StudyList")), ("400", errors "A parameter is not valid.")])
    ]

getOne :: Json
getOne =
  JObject
    [ ("operationId", s "getStudy")
    , ("summary", s "Read one study")
    , ("parameters", JArray [idParameter])
    , ( "responses"
      , JObject
          [ ("200", replyWith "The record, or a tombstone for a hidden study." (ref' "Record"))
          , ("404", errors "No study has this id.")
          ]
      )
    ]

plainText :: Text -> Text -> Text -> Json
plainText operationId summary mime =
  JObject
    [ ("operationId", s operationId)
    , ("summary", s summary)
    , ("responses", JObject [("200", reply summary [("content", JObject [(mime, JObject [("schema", JObject [("type", s "string")])])])])])
    ]

-- | The document. One value; 'text' is its JSON.
document :: Json
document =
  JObject
    [ ("openapi", s "3.1.0")
    , ( "info"
      , JObject
          [ ("title", s "marola study API")
          , ("version", s "1")
          , ( "description"
            , s
                ( "Submit, list and read studies. Every study is public at once and labelled "
                    <> "\"not reviewed, not medical advice\"; the board can hide one later. Guide for agents: /api/v1/skill.md."
                )
            )
          ]
      )
    , ("servers", JArray [JObject [("url", s "https://marola.dev")]])
    , ( "paths"
      , JObject
          [ (StudyApi.apiPath, JObject [("post", post), ("get", get)])
          , (StudyApi.apiPath <> "/{id}", JObject [("get", getOne)])
          , ("/api/v1/skill.md", JObject [("get", plainText "getSkill" "The guide for agents, in Markdown." "text/plain")])
          , (path, JObject [("get", plainText "getOpenApi" "This document." "application/json")])
          ]
      )
    , ( "components"
      , JObject
          [ ( "securitySchemes"
            , JObject
                [ ( "bearerAuth"
                  , JObject
                      [ ("type", s "http")
                      , ("scheme", s "bearer")
                      , ("description", s "An API key (`msk_...`) made on the account page after a GitHub login. Shown once.")
                      ]
                  )
                ]
            )
          , ("schemas", JObject schemas)
          ]
      )
    ]

text :: BL.ByteString
text = render document

response :: Response
response = responseLBS status200 [(hContentType, "application/json; charset=utf-8"), (hCacheControl, "public, max-age=300")] text
