-- | The checks of scripts/server_smoke.sh against a running marola-server: headers, the base map's
-- files and ranges, the pages, hostile paths and the contact form. The inbox command is run (with the
-- server's MAROLA_DB in its environment) to read what POST /contact stored.
module Marola.Tools.Smoke (main) where

import Control.Monad (forM, forM_, unless)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.CaseInsensitive (CI)
import Data.CaseInsensitive qualified as CI
import Data.Char (isAlphaNum, isDigit, isHexDigit)
import Data.List (nub, sort)
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Marola.Tools.Client
import System.Exit (exitFailure)
import System.IO (stderr)
import System.Process (readProcess)

expected :: [(CI ByteString, Text -> Bool)]
expected =
  [ ("content-security-policy", \v -> "script-src 'self'" `T.isInfixOf` v && "form-action 'self'" `T.isInfixOf` v),
    ("strict-transport-security", (== "max-age=63072000; includeSubDomains")),
    ("x-content-type-options", (== "nosniff")),
    ("referrer-policy", (== "strict-origin-when-cross-origin")),
    ("permissions-policy", T.isPrefixOf "geolocation=(self)"),
    ("cross-origin-opener-policy", (== "same-origin")),
    ("cross-origin-resource-policy", (== "same-origin"))
  ]

tshow :: (Show a) => a -> Text
tshow = T.pack . show

orNone :: Maybe Text -> Text
orNone = fromMaybe "undefined"

checkHeaders :: Checks -> Text -> Res -> IO ()
checkHeaders c what r = do
  forM_ expected $ \(name, test) ->
    ok c (maybe False test (hdr name r)) (what <> ": " <> headerName name) (orNone (hdr name r))
  ok c (isNothing (hdr "server" r) && isNothing (hdr "x-powered-by" r)) (what <> ": no Server or X-Powered-By") ""

headerName :: CI ByteString -> Text
headerName = TE.decodeUtf8 . CI.foldedCase

-- | The values of every @attr="..."@ that follows @open@ before the tag closes.
attrValues :: Text -> Text -> Text -> [Text]
attrValues open attr html =
  [ T.takeWhile (/= '"') (T.drop (T.length key) rest)
  | chunk <- drop 1 (T.splitOn open html),
    let tag = T.takeWhile (/= '>') chunk,
    let (_, rest) = T.breakOn key tag,
    not (T.null rest)
  ]
  where
    key = attr <> "=\""

between :: Text -> Text -> Text -> [Text]
between open close t = [T.takeWhile (/= T.head close) chunk | chunk <- drop 1 (T.splitOn open t), close `T.isInfixOf` chunk]

isHtml :: Res -> Bool
isHtml r = maybe False ("text/html" `T.isInfixOf`) (hdr "content-type" r)

main :: [String] -> IO ()
main = \case
  (base : inbox) -> run base inbox
  [] -> fail "usage: marola-tools smoke <base-url> <inbox-command...>"

run :: String -> [String] -> IO ()
run base inbox = do
  m <- newManager
  c <- newChecks "  "
  let g = get m base
      gh = getH m base
      check = ok c
      bodyHas needle r = needle `T.isInfixOf` text r
      cType r = orNone (hdr "content-type" r)

  page <- g "/"
  check (page.status == 200 && isHtml page) "GET / is the page" (tshow page.status)
  check (hdr "cache-control" page == Just "no-cache") "the page is no-cache" ""
  checkHeaders c "/" page

  -- The Elm bundle's name carries Vite's content hash: read it from the page.
  let scripts =
        [ T.drop 1 src
        | src <- attrValues "<script type=\"module\"" "src" (text page),
          "./assets/index-" `T.isPrefixOf` src,
          ".js" `T.isSuffixOf` src,
          T.all (\x -> isAlphaNum x || x == '_' || x == '-') (T.dropEnd 3 (T.drop (T.length "./assets/index-") src))
        ]
      script = case scripts of
        (s : _) -> s
        [] -> "/assets/index.js"
      scriptB = TE.encodeUtf8 script
  module_ <- g scriptB
  check (module_.status == 200 && "text/javascript" `T.isInfixOf` cType module_) ("GET " <> script <> " is JavaScript") (tshow module_.status)
  checkHeaders c script module_

  packed <- gh scriptB [("Accept-Encoding", "br, gzip")]
  check (hdr "content-encoding" packed == Just "br") "JavaScript goes out compressed (br)" (orNone (hdr "content-encoding" packed))

  dat <- g "/data/floripa/latest.json"
  check (dat.status == 200 && "application/json" `T.isInfixOf` cType dat) "GET /data/floripa/latest.json is JSON" (tshow dat.status)
  check (bodyHas "smoke" dat) "/data/ is read from MAROLA_DATA first" ""
  checkHeaders c "/data/floripa/latest.json" dat

  -- The base map: the style and a glyph range as plain files, and the one file that answers byte ranges.
  mapStyle <- gh "/map/style.json" [("Accept-Encoding", "br")]
  check (mapStyle.status == 200 && "application/json" `T.isInfixOf` cType mapStyle && hdr "content-encoding" mapStyle == Just "br") "GET /map/style.json is JSON, compressed" (tshow mapStyle.status)
  glyphs <- gh "/map/fonts/noto-sans-regular/0-255.pbf" [("Accept-Encoding", "br")]
  check (glyphs.status == 200 && hdr "content-type" glyphs == Just "application/x-protobuf" && hdr "content-encoding" glyphs == Just "br") "a glyph range is protobuf, compressed" (tshow glyphs.status <> " " <> cType glyphs)
  check (hdr "cache-control" glyphs == Just "public, max-age=86400") "a glyph range is cached for a day" ""
  let tilesPath = "/tiles/marola.pmtiles"
  tileHead <- gh tilesPath [("Range", "bytes=0-16383"), ("Accept-Encoding", "br, gzip")]
  let contentRange = fromMaybe "" (hdr "content-range" tileHead)
      sizeText = T.takeWhileEnd isDigit contentRange
      tilesSize = if T.null sizeText || not ("/" `T.isSuffixOf` T.dropEnd (T.length sizeText) contentRange) then 0 else read (T.unpack sizeText) :: Integer
      bodyLen r = toInteger (BL.length r.body)
  check (tileHead.status == 206 && bodyLen tileHead == 16384 && hdr "content-length" tileHead == Just "16384") "a range of the tiles file is a 206 with exactly its bytes" (tshow tileHead.status <> " " <> tshow (bodyLen tileHead))
  check (contentRange == "bytes 0-16383/" <> tshow tilesSize && tilesSize > 16384 && hdr "accept-ranges" tileHead == Just "bytes") "with Content-Range and Accept-Ranges" contentRange
  check (BL.take 7 tileHead.body == "PMTiles" && BL.indexMaybe tileHead.body 7 == Just 3) "and they are the header of a PMTiles v3 archive" ""
  check (isNothing (hdr "content-encoding" tileHead) && hdr "content-type" tileHead == Just "application/octet-stream") "the tiles file is never compressed" ""
  let cacheOk = case T.stripPrefix "public, max-age=" (fromMaybe "" (hdr "cache-control" tileHead)) of
        Just n -> not (T.null n) && T.all isDigit n
        Nothing -> False
      etag = fromMaybe "" (hdr "etag" tileHead)
      etagOk = case T.splitOn "-" <$> (T.stripPrefix "\"" =<< T.stripSuffix "\"" etag) of
        Just [a, b] -> not (T.null a) && not (T.null b) && T.all hexLower (a <> b)
        _ -> False
      hexLower x = isHexDigit x && not (x >= 'A' && x <= 'F')
  check (cacheOk && etagOk) "it is cached, under an ETag of size and mtime" (orNone (hdr "cache-control" tileHead) <> " " <> orNone (hdr "etag" tileHead))
  checkHeaders c (TE.decodeUtf8 tilesPath) tileHead
  tileTail <- gh tilesPath [("Range", TE.encodeUtf8 ("bytes=" <> tshow (tilesSize - 10) <> "-"))]
  check (tileTail.status == 206 && bodyLen tileTail == 10 && hdr "content-range" tileTail == Just ("bytes " <> tshow (tilesSize - 10) <> "-" <> tshow (tilesSize - 1) <> "/" <> tshow tilesSize)) "an open range ends at the last byte" (orNone (hdr "content-range" tileTail))
  tileBeyond <- gh tilesPath [("Range", TE.encodeUtf8 ("bytes=" <> tshow tilesSize <> "-"))]
  check (tileBeyond.status == 416 && hdr "content-range" tileBeyond == Just ("bytes */" <> tshow tilesSize)) "a range past the end is a 416 that names the size" (tshow tileBeyond.status)
  checkHeaders c "416" tileBeyond
  tileSame <- gh tilesPath [("If-None-Match", TE.encodeUtf8 etag)]
  check (tileSame.status == 304 && BL.null tileSame.body) "the same ETag gets a 304" (tshow tileSame.status)
  hostTiles <- gh "/tiles/smoke.pmtiles" [("Range", "bytes=0-4")]
  check (hostTiles.status == 206 && text hostTiles == "smoke") "/tiles/ is read from MAROLA_TILES first" (tshow hostTiles.status)
  forM_ ["/tiles/../index.html", "/tiles/%2e%2e/index.html", "/tiles/..%2fmarola.db", "/tiles/smoke.pmtiles/", "/tiles/SMOKE.pmtiles", "/tiles/x/smoke.pmtiles", "/tiles/", "/tiles/nope.pmtiles"] $ \p -> do
    res <- gh p [("Range", "bytes=0-4")]
    check (res.status == 404 && isNothing (hdr "accept-ranges" res)) ("GET " <> TE.decodeUtf8 p <> " is a 404") (tshow res.status)
  pageRange <- gh scriptB [("Range", "bytes=0-9")]
  check (pageRange.status == 200 && isNothing (hdr "accept-ranges" pageRange) && isNothing (hdr "content-range" pageRange)) "no other file answers a range" (tshow pageRange.status)
  let csp = T.toLower (fromMaybe "" (hdr "content-security-policy" page))
  check (not (any (`T.isInfixOf` csp) ["openfreemap", "mapbox", "maptiler"])) "the CSP names no map host" ""

  missing <- g "/nope"
  check (missing.status == 404) "GET /nope is 404" (tshow missing.status)
  check (isHtml missing && bodyHas "<html lang=\"pt-BR\">" missing) "/nope is the pt-BR 404 page" ""
  checkHeaders c "/nope" missing
  missingEn <- g "/en/nope"
  check (missingEn.status == 404 && bodyHas "<html lang=\"en\">" missingEn) "/en/nope is the English 404 page" (tshow missingEn.status)

  -- The pages of back/pages, in both languages (run scripts/site_build.sh first).
  forM_ [("/about.html", "pt-BR"), ("/en/about.html", "en"), ("/contact.html", "pt-BR"), ("/en/contact.html", "en"), ("/contact-sent.html", "pt-BR"), ("/en/support.html", "en")] $ \(p, lang) -> do
    res <- g (TE.encodeUtf8 p)
    check (res.status == 200 && isHtml res && bodyHas ("<html lang=\"" <> lang <> "\">") res) ("GET " <> p <> " is the " <> lang <> " page") (tshow res.status)
    checkHeaders c p res
  clean <- g "/en/about"
  check (clean.status == 200 && bodyHas "<html lang=\"en\">" clean) "/en/about finds en/about.html" (tshow clean.status)

  -- Every page of both languages, and the files that are not pages: status, content type, language, and
  -- that each site link on a page (the nav above all) answers 200. A page that moves or goes missing fails here.
  let slugs = ["about", "news", "contact", "members", "support", "contact-sent"] :: [Text]
  links <- fmap concat . forM [("", "pt-BR"), ("/en", "en")] $ \(prefix, lang) ->
    fmap concat . forM slugs $ \slug -> do
      let p = prefix <> "/" <> slug <> ".html"
      res <- g (TE.encodeUtf8 p)
      check (res.status == 200 && hdr "content-type" res == Just "text/html; charset=utf-8" && bodyHas ("<html lang=\"" <> lang <> "\">") res) ("GET " <> p <> " is a " <> lang <> " html page") (tshow res.status <> " " <> cType res)
      pure
        [ T.takeWhile (/= '?') (T.takeWhile (/= '#') target)
        | href <- attrValues "<a " "href" (text res),
          let target = T.replace "&amp;" "&" href,
          "/" `T.isPrefixOf` target,
          not ("//" `T.isPrefixOf` target)
        ]
  forM_ (sort (nub links)) $ \target -> do
    res <- g (TE.encodeUtf8 target)
    check (res.status == 200) ("the page link " <> target <> " answers 200") (tshow res.status)
  forM_
    [ ("/robots.txt", "text/plain"),
      ("/sitemap.xml", "application/xml"),
      ("/llms.txt", "text/plain"),
      ("/humans.txt", "text/plain"),
      ("/.well-known/security.txt", "text/plain"),
      ("/favicon.svg", "image/svg+xml"),
      ("/board.schema.json", "application/json")
    ]
    $ \(p, typ) -> do
      res <- g (TE.encodeUtf8 p)
      check (res.status == 200 && typ `T.isPrefixOf` cType res) ("GET " <> p <> " answers 200 as " <> typ) (tshow res.status <> " " <> cType res)
  security <- text <$> g "/.well-known/security.txt"
  let secLines = T.lines security
      expires l = case T.stripPrefix "Expires: " l of
        Just d -> T.length d == 20 && T.all isDigit (T.take 4 d) && T.index d 4 == '-' && T.all isDigit (T.take 2 (T.drop 5 d)) && T.index d 7 == '-' && T.all isDigit (T.take 2 (T.drop 8 d)) && T.drop 10 d == "T00:00:00Z"
        Nothing -> False
  check (any (T.isPrefixOf "Contact: https://") secLines && any expires secLines) "security.txt has Contact and Expires" ""
  sitemap <- text <$> g "/sitemap.xml"
  let locs = [T.replace "https://marola.dev" "" l | l <- between "<loc>" "<" sitemap]
  forM_ locs $ \loc -> do
    res <- g (TE.encodeUtf8 (T.takeWhile (/= '?') loc))
    check (res.status == 200) ("the sitemap page " <> loc <> " answers 200") (tshow res.status)
  check (not (any ("contact" `T.isInfixOf`) locs)) "no contact page in the sitemap" ""
  forM_ ["/.well-known/.hidden", "/.env", "/sub/.well-known/security.txt"] $ \p -> do
    res <- g p
    check (res.status == 404) (TE.decodeUtf8 p <> " is 404") ""

  headRes <- send m base "HEAD" "/" [] mempty
  check (headRes.status == 200 && BL.null headRes.body) "HEAD / has no body" ""
  checkHeaders c "HEAD /" headRes

  forM_ ["/..%2f..%2f..%2fetc/passwd", "/%2e%2e/%2e%2e/etc/passwd", "/..%5c..%5cetc/passwd", "//etc/passwd", "/assets/../../etc/passwd", "/%00", "/.git/config", "/vendor/.gitignore", "/assets/"] $ \p -> do
    res <- g p
    let pt = TE.decodeUtf8 p
    check (res.status == 404 || res.status == 400) ("hostile path " <> pt <> " is refused (" <> tshow res.status <> ")") (tshow res.status)
    check (not (bodyHas "root:" res)) ("hostile path " <> pt <> " leaks nothing") ""

  let origin = TE.encodeUtf8 (T.pack (takeWhile (/= '/') (drop 7 base)))
      originH = [("Origin", "http://" <> origin)]
      good = [("email", "smoke@example.org"), ("message", "A smoke test message, ten characters or more."), ("website", "")]
  sent <- postForm m base "/contact" originH good
  check (sent.status == 303 && hdr "location" sent == Just "/contact-sent.html") "POST /contact with the site's Origin: 303 to /contact-sent.html" (tshow sent.status)
  checkHeaders c "POST /contact" sent
  noOrigin <- postForm m base "/contact" [] good
  check (noOrigin.status == 403) "POST /contact without an Origin: 403" (tshow noOrigin.status)
  evil <- postForm m base "/contact" [("Origin", "https://evil.example")] good
  check (evil.status == 403) "POST /contact from another site: 403" (tshow evil.status)
  botRes <- postForm m base "/contact" originH [("email", "bot@example.org"), ("message", "buy my pills, please buy"), ("website", "http://spam.example")]
  check (botRes.status == 200) "the honeypot gets 200" (tshow botRes.status)

  listing <-
    T.pack <$> case inbox of
      (cmd : args) -> readProcess cmd args ""
      [] -> pure ""
  check ("smoke@example.org" `T.isInfixOf` listing && "A smoke test message" `T.isInfixOf` listing) "marola-server inbox shows the stored message" ""
  check (not ("bot@example.org" `T.isInfixOf` listing) && T.count "smoke@example.org" listing == 1) "the honeypot post and the refused posts are not stored" ""

  n <- failures c
  unless (n == 0) $ do
    TIO.hPutStrLn stderr ("server_smoke: " <> tshow n <> " check(s) failed")
    exitFailure
  TIO.putStrLn "server_smoke: all checks passed"
