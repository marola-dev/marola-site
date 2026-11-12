module TileSpec (spec) where

import Control.Monad (forM_, replicateM)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BC
import Data.Text qualified as T
import Harness
import Marola.Server.App qualified as App
import Marola.Server.Security qualified as Security
import Marola.Server.Tiles (rangeOf)
import Marola.Server.Tiles qualified as Tiles
import Test.Hspec

tiles :: ByteString
tiles = "/tiles/marola.pmtiles"

ranged :: ByteString -> ByteString -> Req
ranged p r = (get p) {headers = [("Range", r)]}

spec :: Spec
spec = describe "the base map's tiles" $ do
  it "a range is a 206 with its bytes, Content-Range, Content-Length and Accept-Ranges" $ withSite $ \site ->
    forM_
      [ ("bytes=0-15", "bytes 0-15/1000", "0000000100020003"),
        ("bytes=400-407", "bytes 400-407/1000", "01000101"),
        ("bytes=996-", "bytes 996-999/1000", "0249"),
        ("bytes=-8", "bytes 992-999/1000", "02480249"),
        ("bytes=992-5000", "bytes 992-999/1000", "02480249"),
        ("bytes=-5000", "bytes 0-999/1000", tileBytes),
        (" bytes=4-7 ", "bytes 4-7/1000", "0001")
      ]
      $ \(r, contentRange, body) -> do
        res <- send site (ranged tiles r)
        (r, res.status) `shouldBe` (r, 206)
        (r, header res "Content-Range") `shouldBe` (r, Just contentRange)
        (r, header res "Content-Length") `shouldBe` (r, Just (BC.pack (show (T.length body))))
        (r, header res "Accept-Ranges") `shouldBe` (r, Just "bytes")
        (r, header res "Content-Type") `shouldBe` (r, Just "application/octet-stream")
        (r, bodyText res) `shouldBe` (r, body)

  it "no Range is the whole file, and it says that ranges are answered" $ withSite $ \site -> do
    res <- send site (get tiles)
    res.status `shouldBe` 200
    bodyText res `shouldBe` tileBytes
    header res "Content-Length" `shouldBe` Just "1000"
    header res "Accept-Ranges" `shouldBe` Just "bytes"
    header res "Content-Range" `shouldBe` Nothing
    -- RFC 9110: a unit the server does not know is ignored.
    other <- send site (ranged tiles "items=0-5")
    (other.status, bodyText other) `shouldBe` (200, tileBytes)

  it "a range that cannot be answered is a 416 that names the size" $ withSite $ \site ->
    forM_ ["bytes=1000-", "bytes=1000-1001", "bytes=5-2", "bytes=-0", "bytes=a-b", "bytes=0-1,5-6", "bytes=", "bytes=-", "bytes=1-2-3", "bytes=0x10-20", "bytes=1 - 2", "bytes=99999999999999999999-"] $ \r -> do
      res <- send site (ranged tiles r)
      (r, res.status) `shouldBe` (r, 416)
      (r, header res "Content-Range") `shouldBe` (r, Just "bytes */1000")
      (r, bodyText res) `shouldBe` (r, "range not satisfiable\n")

  it "rangeOf: first and last byte inside the file, or nothing" $ do
    rangeOf 10 Nothing `shouldBe` Tiles.Whole
    rangeOf 10 (Just "bytes=0-0") `shouldBe` Tiles.Part 0 0
    rangeOf 10 (Just "bytes=9-") `shouldBe` Tiles.Part 9 9
    rangeOf 10 (Just "bytes=10-") `shouldBe` Tiles.Unsatisfiable
    rangeOf 10 (Just "bytes=-3") `shouldBe` Tiles.Part 7 9
    rangeOf 0 (Just "bytes=-3") `shouldBe` Tiles.Unsatisfiable
    rangeOf 0 (Just "bytes=0-") `shouldBe` Tiles.Unsatisfiable

  it "every answer has the security headers, and the file is never compressed" $ withSite $ \site ->
    forM_ [(ranged tiles "bytes=0-99", 206), (get tiles, 200), (ranged tiles "bytes=2000-", 416), (get "/tiles/nope.pmtiles", 404), ((get tiles) {method = "HEAD"}, 200), ((get tiles) {method = "POST"}, 405)] $ \(r, st) -> do
      res <- send site r {headers = r.headers <> [("Accept-Encoding", "br, gzip")]}
      (r.method, res.status) `shouldBe` (r.method, st)
      forM_ Security.responseHeaders $ \(n, v) -> (st, n, header res n) `shouldBe` (st, n, Just v)
      (st, st < 400 && header res "Content-Encoding" /= Nothing) `shouldBe` (st, False)

  it "the ETag: a day of cache, a 304 for the same file, and If-Range" $ withSite $ \site -> do
    first <- send site (ranged tiles "bytes=0-3")
    let Just etag = header first "ETag"
    header first "Cache-Control" `shouldBe` Just "public, max-age=86400"
    same <- send site (get tiles) {headers = [("If-None-Match", etag)]}
    same.status `shouldBe` 304
    current <- send site (get tiles) {headers = [("Range", "bytes=0-3"), ("If-Range", etag)]}
    (current.status, bodyText current) `shouldBe` (206, "0000")
    -- A range computed against an older file must not be cut out of the new one.
    stale <- send site (get tiles) {headers = [("Range", "bytes=0-3"), ("If-Range", "\"old\"")]}
    (stale.status, bodyText stale) `shouldBe` (200, tileBytes)

  it "only a plain <name>.pmtiles is a tiles file; anything else is a 404 and never the secret" $ withSite $ \site ->
    forM_
      [ "/tiles/secret.txt",
        "/tiles/../secret.txt",
        "/tiles/%2e%2e/secret.txt",
        "/tiles/..%2fsecret.txt",
        "/tiles/..%2ftiles%2fmarola.pmtiles",
        "/tiles/sub/marola.pmtiles",
        "/tiles/marola.pmtiles/",
        "/tiles/MAROLA.pmtiles",
        "/tiles/marola.PMTILES",
        "/tiles/.pmtiles",
        "/tiles/..pmtiles",
        "/tiles/a.b.pmtiles",
        "/tiles/marola.pmtiles%00",
        "/tiles/marola.pmtiles\NUL.txt",
        "/tiles/marola pmtiles",
        "/tiles/",
        "/tiles/nope.pmtiles"
      ]
      $ \p -> do
        res <- send site (ranged p "bytes=0-3")
        (p, res.status) `shouldBe` (p, 404)
        (p, secret `T.isInfixOf` bodyText res) `shouldBe` (p, False)
        (p, bodyText res) `shouldBe` (p, "not found\n")

  it "archive names the file of a path" $ do
    Tiles.archive "/tiles/marola.pmtiles" `shouldBe` Just "marola.pmtiles"
    Tiles.archive "/tiles/br-2026.pmtiles" `shouldBe` Just "br-2026.pmtiles"
    Tiles.archive ("/tiles/" <> T.replicate 65 "a" <> ".pmtiles") `shouldBe` Nothing
    Tiles.archive "/tiles/a_b.pmtiles" `shouldBe` Nothing
    Tiles.archive "/data/marola.pmtiles" `shouldBe` Nothing

  it "the tiles folder answers first, the build's own tiles/ second" $ withSite $ \site -> do
    host <- send site (ranged tiles "bytes=0-3")
    bodyText host `shouldBe` "0000"
    build <- send site (get "/tiles/fixture.pmtiles")
    (build.status, bodyText build) `shouldBe` (200, "the build's fixture")

  it "no other file answers a range" $ withSite $ \site ->
    forM_ ["/app.js", "/font.woff2", "/data/floripa/latest.json", "/"] $ \p -> do
      res <- send site (ranged p "bytes=0-3")
      (p, res.status) `shouldBe` (p, 200)
      (p, header res "Accept-Ranges", header res "Content-Range") `shouldBe` (p, Nothing, Nothing)

  it "tiles have a limit of their own, and do not spend the page's" $ withSite $ \site -> do
    codes <- replicateM (App.generalPermits + 1) ((.status) <$> send site (ranged tiles "bytes=0-3"))
    codes `shouldBe` replicate (App.generalPermits + 1) 206
    page <- send site (get "/index.html")
    page.status `shouldBe` 200
    more <- replicateM (Tiles.permits - App.generalPermits) ((.status) <$> send site (ranged tiles "bytes=0-3"))
    last more `shouldBe` 429
