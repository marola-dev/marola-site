module OpenApiSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson qualified as A
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Char8 qualified as BC
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Scientific (toBoundedInteger)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Harness
import Marola.Server.App qualified as App
import Marola.Server.Http (Route (..))
import Marola.Server.Messages qualified as Messages
import Marola.Server.OpenApi qualified as OpenApi
import Marola.Server.PdfIntake qualified as PdfIntake
import Marola.Server.StudyApi qualified as StudyApi
import Marola.Study
import Test.Hspec

document :: A.Value
document = fromJust (A.decode OpenApi.text)

submitSchema :: A.Value
submitSchema = jpath ["paths", "/api/v1/studies", "post", "requestBody", "content", "multipart/form-data", "schema"] document

fieldOf :: Text -> A.Value
fieldOf n = jpath ["properties", n] submitSchema

number :: A.Value -> Text -> Int
number e n = case jpath [n] e of
  A.Number x -> fromJust (toBoundedInteger x)
  other -> error ("not a number: " <> show (n, other))

keys :: A.Value -> [Text]
keys (A.Object o) = map K.toText (KM.keys o)
keys _ = []

strings :: A.Value -> [Text]
strings (A.Array xs) = [t | A.String t <- toList xs]
strings _ = []

documented :: Set.Set (Text, Text)
documented = Set.fromList [(op, p) | p <- keys (jpath ["paths"] document), op <- keys (jpath ["paths", p] document)]

registered :: Set.Set (Text, Text)
registered = Set.fromList [(T.toLower (TE.decodeUtf8 r.method), r.pattern) | r <- App.routes, "/api/v1" `T.isPrefixOf` r.pattern]

goodFields :: Map.Map Text Text
goodFields =
  Map.fromList
    [ ("title", "Enterococcus in Praia do Leblon, 2025")
    , ("authors", "Ana Silva | 0000-0002-1825-0097\nBruno Costa")
    , ("abstract", T.replicate 12 "Sampling of bathing water. ")
    , ("area", "rio")
    , ("topic", "water-quality")
    , ("sources", "https://example.org/data")
    , ("rights", "true")
    , ("ai_contribution", "none")
    ]

fieldErrors :: Text -> Text -> [Text]
fieldErrors n v = case validate (\k -> if k == n then Just v else Map.lookup k goodFields) of
  Right _ -> []
  Left es -> [e.code | e <- es, e.field == n]

accepted :: Text -> Text -> Bool
accepted n v = null (fieldErrors n v)

text :: Int -> Text
text n = T.replicate n "a"

-- | Checks min and max of a length-limited field against the validation.
bounds :: Text -> Maybe Int -> Int -> IO ()
bounds n lo hi = do
  let f = fieldOf n
  forM_ lo $ \m -> do
    number f "minLength" `shouldBe` m
    (n, accepted n (text (m - 1))) `shouldBe` (n, False)
    (n, accepted n (text m)) `shouldBe` (n, True)
  number f "maxLength" `shouldBe` hi
  (n, accepted n (text hi)) `shouldBe` (n, True)
  (n, accepted n (text (hi + 1))) `shouldBe` (n, False)

spec :: Spec
spec = describe "openapi" $ do
  it "the document is served as JSON, cached 300 s, with the headers of every route" $ withSite $ \site -> do
    r <- send site (get "/api/v1/openapi.json")
    r.status `shouldBe` 200
    header r "Content-Type" `shouldBe` Just "application/json; charset=utf-8"
    header r "Cache-Control" `shouldBe` Just "public, max-age=300"
    header r "X-Content-Type-Options" `shouldBe` Just "nosniff"
    header r "Content-Security-Policy" `shouldSatisfy` (/= Nothing)
    header r "Strict-Transport-Security" `shouldSatisfy` (/= Nothing)
    r.body `shouldBe` OpenApi.text
    jtext ["openapi"] document `shouldBe` "3.1.0"

  it "every route under /api/v1 is in the document with the same method, and every documented path is a route" $ do
    registered `shouldNotBe` Set.empty
    Set.difference registered documented `shouldBe` Set.empty
    Set.difference documented registered `shouldBe` Set.empty

  it "every $ref points at a schema that exists" $ do
    let raw = TE.decodeUtf8 (BC.toStrict OpenApi.text)
        refs = [T.takeWhile (`elem` (['A' .. 'Z'] <> ['a' .. 'z'])) piece | piece <- drop 1 (T.splitOn "#/components/schemas/" raw)]
        schemas = keys (jpath ["components", "schemas"] document)
    refs `shouldNotBe` []
    forM_ refs $ \n -> (n, n `elem` schemas) `shouldBe` (n, True)

  it "the submit operation has the Bearer scheme and the documented status codes" $ do
    jtext ["components", "securitySchemes", "bearerAuth", "type"] document `shouldBe` "http"
    jtext ["components", "securitySchemes", "bearerAuth", "scheme"] document `shouldBe` "bearer"
    let post' = jpath ["paths", "/api/v1/studies", "post"] document
        A.Array security = jpath ["security"] post'
        A.Array params = jpath ["parameters"] post'
    jpath ["bearerAuth"] (head (toList security)) `shouldBe` A.Array mempty
    forM_ ["201", "400", "401", "409", "413", "415", "429", "507"] $ \c -> keys (jpath ["responses"] post') `shouldContain` [c]
    let dry = head (toList params)
    jtext ["name"] dry `shouldBe` "dry_run"
    jtext ["in"] dry `shouldBe` "query"

  it "the error code enum holds every code the API can send and the guide lists" $ do
    let enum = strings (jpath ["components", "schemas", "Error", "properties", "code", "enum"] document)
        guide = snd (T.breakOn "## Errors" StudyApi.skill)
        listed = [w | (i, w) <- zip [0 :: Int ..] (T.splitOn "`" guide), odd i, not (T.null w), T.all (\c -> c `elem` ['a' .. 'z'] || c == '_') w, w /= "id"]
    listed `shouldNotBe` []
    forM_ listed $ \c -> (c, c `elem` enum) `shouldBe` (c, True)
    forM_ (filter (/= "csrf") Messages.codes) $ \c -> (c, c `elem` enum) `shouldBe` (c, True)
    enum `shouldContain` ["not_found"]
    enum `shouldNotContain` ["csrf"]

  it "the document limits are the validation limits: title" $ bounds "title" (Just titleMin) titleMax
  it "the document limits are the validation limits: abstract" $ bounds "abstract" (Just abstractMin) abstractMax
  it "the document limits are the validation limits: ai_models and ai_process" $ do
    bounds "ai_models" Nothing aiModelsMax
    bounds "ai_process" Nothing aiProcessMax

  it "the document limits are the validation limits: authors" $ do
    let f = fieldOf "authors"
        lines'' n = T.intercalate "\n" ["Author " <> T.pack (show i) | i <- [1 .. n]]
    number f "x-max-lines" `shouldBe` authorsMax
    number f "x-name-min-length" `shouldBe` authorNameMin
    number f "x-name-max-length" `shouldBe` authorNameMax
    accepted "authors" (lines'' (number f "x-max-lines")) `shouldBe` True
    accepted "authors" (lines'' (number f "x-max-lines" + 1)) `shouldBe` False
    accepted "authors" (text (authorNameMin - 1)) `shouldBe` False
    accepted "authors" (text authorNameMin) `shouldBe` True
    accepted "authors" (text authorNameMax) `shouldBe` True
    accepted "authors" (text (authorNameMax + 1)) `shouldBe` False

  it "the document limits are the validation limits: sources and links" $ do
    let f = fieldOf "sources"
        base = "https://example.org/"
        link n = base <> text (n - T.length base)
        lines'' n = T.intercalate "\n" [base <> T.pack (show i) | i <- [1 .. n]]
    number f "x-max-lines" `shouldBe` sourcesMax
    number f "x-max-line-length" `shouldBe` linkMax
    accepted "sources" (lines'' sourcesMax) `shouldBe` True
    accepted "sources" (lines'' (sourcesMax + 1)) `shouldBe` False
    accepted "sources" (link linkMax) `shouldBe` True
    accepted "sources" (link (linkMax + 1)) `shouldBe` False
    number (fieldOf "repository") "maxLength" `shouldBe` linkMax
    accepted "repository" (link linkMax) `shouldBe` True
    accepted "repository" (link (linkMax + 1)) `shouldBe` False

  it "the document limits are the validation limits: enums, licence default and the file" $ do
    let values n = strings (jpath ["enum"] (fieldOf n))
    values "area" `shouldBe` areaValues
    values "topic" `shouldBe` topicValues
    values "licence" `shouldBe` licenceValues
    values "ai_contribution" `shouldBe` levelValues
    jtext ["default"] (fieldOf "licence") `shouldBe` licenceName CcBy40
    forM_ [("area", areaValues), ("topic", topicValues), ("licence", licenceValues)] $ \(n, vs) -> do
      forM_ vs $ \v -> (n, v, accepted n v) `shouldBe` (n, v, True)
      (n, accepted n "nope") `shouldBe` (n, False)
    fromIntegral (number (fieldOf "pdf") "x-max-bytes") `shouldBe` PdfIntake.maxBytes
    number submitSchema "x-max-parts" `shouldBe` StudyApi.maxParts
    number submitSchema "x-max-field-bytes" `shouldBe` StudyApi.maxFieldBytes
    fromIntegral (number submitSchema "x-max-request-bytes") `shouldBe` StudyApi.uploadLimit

  it "the document limits are the list limits: limit 1 to the maximum, default as documented" $ do
    let A.Array ps = jpath ["paths", "/api/v1/studies", "get", "parameters"] document
        limit = jpath ["schema"] (head [p | p <- toList ps, jtext ["name"] p == "limit"])
    number limit "minimum" `shouldBe` 1
    number limit "maximum" `shouldBe` StudyApi.listMax
    number limit "default" `shouldBe` StudyApi.listDefault
    withSite $ \site ->
      forM_ [(1, 200), (StudyApi.listMax, 200), (0, 400), (StudyApi.listMax + 1, 400)] $ \(v, expected) -> do
        r <- send site (get ("/api/v1/studies?limit=" <> BC.pack (show v)))
        (v, r.status) `shouldBe` (v, expected)
