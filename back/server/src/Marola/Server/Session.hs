-- | The cookies of the login and the CSRF token of a session. Nothing here is logged.
module Marola.Server.Session
  ( sessionCookie
  , stateCookie
  , safeEquals
  , loadKey
  , csrfToken
  , csrfValid
  , Live (..)
  , current
  , setCookie
  , clearCookie
  )
where

import Control.Exception (IOException, catch)
import Crypto.Hash (SHA256)
import Crypto.MAC.HMAC (HMAC, hmac)
import Data.ByteArray (constEq, convert)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (toUpper)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Time (NominalDiffTime, UTCTime)
import Marola.Server.StudyStore (Account, getSession, randomBytes)
import System.Directory (createDirectoryIfMissing, doesFileExist, makeAbsolute)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose)
import System.Posix.Files (ownerReadMode, ownerWriteMode, unionFileModes)
import System.Posix.IO (OpenFileFlags (..), OpenMode (WriteOnly), defaultFileFlags, fdToHandle, openFd)

-- @__Host-@ makes a browser refuse the cookie unless it is Secure, has Path=/ and names no Domain.
-- Dev mode (plain HTTP on 127.0.0.1) cannot carry @Secure@, so it uses the bare names.
sessionCookie :: Bool -> ByteString
sessionCookie dev = if dev then "msess" else "__Host-msess"

stateCookie :: Bool -> ByteString
stateCookie dev = if dev then "mstate" else "__Host-mstate"

-- | Equal text in time that does not depend on where the texts differ.
safeEquals :: Text -> Text -> Bool
safeEquals a b =
  let x = TE.encodeUtf8 a
      y = TE.encodeUtf8 b
   in BS.length x == BS.length y && constEq x y

-- | The HMAC key of the CSRF tokens: made at the first start next to the database, mode 0600, and
-- read afterwards. A restart keeps it, so a form opened before a deploy still posts. The file is the
-- F# server's: 64 upper-case hex digits.
loadKey :: FilePath -> IO ByteString
loadKey db = do
  dir <- takeDirectory <$> makeAbsolute db
  createDirectoryIfMissing True dir
  let path = dir </> "csrf.key"
      readKey = do
        text <- BC.strip <$> BS.readFile path
        either (\e -> fail ("csrf.key: " <> e)) pure (convertFromBase Base16 (BC.map toLower' text))
      create = do
        key <- randomBytes 32
        fd <- openFd path WriteOnly defaultFileFlags {exclusive = True, creat = Just (unionFileModes ownerReadMode ownerWriteMode)}
        h <- fdToHandle fd
        BS.hPut h (BC.map toUpper (convertToBase Base16 key))
        hClose h
        pure key
  exists <- doesFileExist path
  if exists
    then readKey
    else create `catch` \(_ :: IOException) -> readKey -- another start made it between the check and the create
  where
    toLower' c = if c >= 'A' && c <= 'F' then toEnum (fromEnum c + 32) else c

-- | The hidden field of every POST form: an HMAC of the session's id, so it is bound to one login.
csrfToken :: ByteString -> Text -> Text
csrfToken key sessionHash =
  let mac = hmac key (TE.encodeUtf8 ("csrf:" <> sessionHash)) :: HMAC SHA256
   in TE.decodeUtf8 (convertToBase Base16 (convert mac :: ByteString))

csrfValid :: ByteString -> Text -> Text -> Bool
csrfValid key sessionHash supplied = safeEquals (csrfToken key sessionHash) supplied

data Live = Live
  { account :: Account
  , token :: Text
  -- ^ The cookie value: needed to delete the row at logout.
  , hash :: Text
  -- ^ What 'csrfToken' takes.
  }

-- | The logged-in visitor of this request: no cookie, a forged or an expired value is 'Nothing'.
current :: FilePath -> UTCTime -> Maybe Text -> IO (Maybe Live)
current db now = \case
  Nothing -> pure Nothing
  Just tok -> fmap (\(a, h) -> Live a tok h) <$> getSession db now tok

-- | The @Set-Cookie@ value, in the words and the order ASP.NET Core writes them.
setCookie :: Bool -> ByteString -> Text -> NominalDiffTime -> ByteString
setCookie dev name value maxAge =
  name <> "=" <> TE.encodeUtf8 value <> "; max-age=" <> BC.pack (show (floor maxAge :: Int)) <> attrs dev

clearCookie :: Bool -> ByteString -> ByteString
clearCookie dev name = name <> "=; expires=Thu, 01 Jan 1970 00:00:00 GMT; max-age=0" <> attrs dev

attrs :: Bool -> ByteString
attrs dev = "; path=/" <> (if dev then "" else "; secure") <> "; samesite=lax; httponly"
