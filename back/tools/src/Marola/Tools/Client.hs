-- | A small HTTP client for the smoke runs: the exact path bytes a hostile client sends (no
-- normalising of ".."), no redirects followed, no cookie jar, no decompression, and no proxy.
module Marola.Tools.Client
  ( Res (..),
    Checks,
    newChecks,
    failures,
    ok,
    newManager,
    send,
    get,
    getH,
    postForm,
    postMultipart,
    hdr,
    hdrs,
    text,
    json,
    field,
    str,
    formEncode,
  )
where

import Data.Aeson qualified as A
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.CaseInsensitive (CI)
import Data.IORef
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error (lenientDecode)
import Data.Text.IO qualified as TIO
import Network.HTTP.Client qualified as H
import Network.HTTP.Client.MultipartFormData (Part, formDataBody)
import Network.HTTP.Types (renderSimpleQuery, statusCode)

data Res = Res {status :: Int, headers :: [(CI ByteString, ByteString)], body :: BL.ByteString}

-- | Counts the failed checks; the prefix is how each line starts ("  " for the main run).
data Checks = Checks Text (IORef Int)

newChecks :: Text -> IO Checks
newChecks prefix = Checks prefix <$> newIORef 0

failures :: Checks -> IO Int
failures (Checks _ ref) = readIORef ref

ok :: Checks -> Bool -> Text -> Text -> IO ()
ok (Checks prefix ref) cond label detail = do
  TIO.putStrLn (prefix <> (if cond then "ok   " else "FAIL ") <> label <> (if not cond && not (T.null detail) then ": " <> detail else ""))
  if cond then pure () else modifyIORef' ref (+ 1)

newManager :: IO H.Manager
newManager = H.newManager (H.managerSetProxy H.noProxy H.defaultManagerSettings)

-- | One request to @base <> path@, where the path (and its query) are sent as they are.
send :: H.Manager -> String -> ByteString -> ByteString -> [(CI ByteString, ByteString)] -> H.RequestBody -> IO Res
send manager base method rawPath extra reqBody = do
  initial <- H.parseRequest base
  let (p, q) = BC.break (== '?') rawPath
      -- http-client asks for gzip when a request names no encoding; a browser-less client asks for none.
      encoding = [("Accept-Encoding", "identity") | not (any ((== "accept-encoding") . fst) extra)]
      req =
        initial
          { H.method = method,
            H.path = p,
            H.queryString = q,
            H.requestHeaders = extra <> encoding,
            H.requestBody = reqBody,
            H.redirectCount = 0,
            H.cookieJar = Nothing,
            H.decompress = const False
          }
  res <- H.httpLbs req manager
  pure (Res (statusCode (H.responseStatus res)) (H.responseHeaders res) (H.responseBody res))

get :: H.Manager -> String -> ByteString -> IO Res
get manager base p = send manager base "GET" p [] mempty

getH :: H.Manager -> String -> ByteString -> [(CI ByteString, ByteString)] -> IO Res
getH manager base p hs = send manager base "GET" p hs mempty

formEncode :: [(ByteString, ByteString)] -> ByteString
formEncode = B.drop 1 . renderSimpleQuery True

postForm :: H.Manager -> String -> ByteString -> [(CI ByteString, ByteString)] -> [(ByteString, ByteString)] -> IO Res
postForm manager base p hs fields =
  send manager base "POST" p (("Content-Type", "application/x-www-form-urlencoded") : hs) (H.RequestBodyBS (formEncode fields))

postMultipart :: H.Manager -> String -> ByteString -> [(CI ByteString, ByteString)] -> [Part] -> IO Res
postMultipart manager base p hs parts = do
  initial <- H.parseRequest base
  withBody <- formDataBody parts initial
  let contentType = [(k, v) | (k, v) <- H.requestHeaders withBody, k == "Content-Type"]
  send manager base "POST" p (contentType <> hs) (H.requestBody withBody)

hdr :: CI ByteString -> Res -> Maybe Text
hdr name r = TE.decodeUtf8With lenientDecode <$> lookup name r.headers

hdrs :: CI ByteString -> Res -> [ByteString]
hdrs name r = [v | (k, v) <- r.headers, k == name]

text :: Res -> Text
text r = TE.decodeUtf8With lenientDecode (BL.toStrict r.body)

json :: Res -> A.Value
json r = maybe A.Null id (A.decode r.body)

field :: Text -> A.Value -> A.Value
field k = \case
  A.Object o -> maybe A.Null id (KM.lookup (K.fromText k) o)
  _ -> A.Null

str :: A.Value -> Maybe Text
str = \case
  A.String s -> Just s
  _ -> Nothing
