-- | A streaming multipart/form-data reader with fixed limits: the preamble and each part's headers at most 4096 bytes, at most 8 headers a part. A body
-- that breaks the framing throws 'Malformed'; nothing is ever buffered whole.
module Marola.Server.Multipart
  ( Malformed (..)
  , Reader
  , Part (..)
  , boundaryOf
  , newReader
  , nextPart
  , dispositionName
  )
where

import Control.Exception (Exception, throwIO)
import Control.Monad (when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.CaseInsensitive qualified as CI
import Data.IORef

data Malformed = Malformed String deriving (Show)

instance Exception Malformed

data Reader = Reader
  { source :: IO ByteString
  , buffer :: IORef ByteString
  , ended :: IORef Bool
  -- ^ The source returned its last chunk.
  , delimiter :: ByteString
  -- ^ @\\r\\n--boundary@
  , state :: IORef State
  }

-- | 'Between': a part's closing delimiter was consumed, what follows it is not read yet.
data State = Start | InPart | Between | Done deriving (Eq)

data Part = Part
  { headers :: [(CI.CI ByteString, ByteString)]
  , body :: IO ByteString
  -- ^ The next piece of the part's body; empty at its end.
  }

limit :: Int
limit = 4096

-- | The boundary of a @multipart/form-data@ content type, its quotes removed.
boundaryOf :: ByteString -> Maybe ByteString
boundaryOf contentType =
  let params = drop 1 (BC.split ';' contentType)
      pairs = [(CI.mk (BC.strip k), BC.strip (BS.drop 1 v)) | p <- params, let (k, v) = BC.break (== '=') p]
   in unquote <$> lookup "boundary" pairs

unquote :: ByteString -> ByteString
unquote v
  | BS.length v >= 2 && BC.head v == '"' && BC.last v == '"' = BS.init (BS.tail v)
  | otherwise = v

-- | The @name@ of a part's Content-Disposition, "" when it has none.
dispositionName :: Part -> ByteString
dispositionName p = case lookup "content-disposition" p.headers of
  Nothing -> ""
  Just v ->
    let items = map BC.strip (BC.split ';' v)
        params = [(CI.mk (BC.strip k), BC.strip (BS.drop 1 val)) | i <- drop 1 items, let (k, val) = BC.break (== '=') i]
     in case items of
          (kind : _) | not (BS.null kind) -> maybe "" unquote (lookup "name" params)
          _ -> ""

newReader :: ByteString -> IO ByteString -> IO Reader
newReader boundary source =
  Reader source <$> newIORef BS.empty <*> newIORef False <*> pure ("\r\n--" <> boundary) <*> newIORef Start

-- | Reads more from the source into the buffer; False at the end of the body.
fill :: Reader -> IO Bool
fill r = do
  done <- readIORef r.ended
  if done
    then pure False
    else do
      chunk <- r.source
      if BS.null chunk
        then writeIORef r.ended True >> pure False
        else modifyIORef' r.buffer (<> chunk) >> pure True

-- | Drops bytes until @needle@ has been consumed, at most @maxSkip@ bytes before it.
skipPast :: Reader -> ByteString -> Int -> IO ()
skipPast r needle maxSkip = do
  b <- readIORef r.buffer
  let (before, rest) = BS.breakSubstring needle b
  if not (BS.null rest)
    then do
      when (BS.length before > maxSkip) (throwIO (Malformed "the preamble is too long"))
      writeIORef r.buffer (BS.drop (BS.length needle) rest)
    else do
      when (BS.length b - BS.length needle > maxSkip) (throwIO (Malformed "the preamble is too long"))
      more <- fill r
      if more then skipPast r needle maxSkip else throwIO (Malformed "unexpected end of the body")

-- | At least @n@ bytes in the buffer, or the end.
ensure :: Reader -> Int -> IO ByteString
ensure r n = do
  b <- readIORef r.buffer
  if BS.length b >= n
    then pure b
    else do
      more <- fill r
      if more then ensure r n else pure b

-- | A CRLF-terminated line, without the CRLF, of at most @budget@ bytes.
line :: Reader -> Int -> IO ByteString
line r budget = do
  b <- readIORef r.buffer
  let (l, rest) = BS.breakSubstring "\r\n" b
  if not (BS.null rest)
    then do
      when (BS.length l > budget) (throwIO (Malformed "the headers are too long"))
      writeIORef r.buffer (BS.drop 2 rest)
      pure l
    else do
      when (BS.length b > budget + 1) (throwIO (Malformed "the headers are too long"))
      more <- fill r
      if more then line r budget else throwIO (Malformed "unexpected end of the body")

-- | After a boundary: @--@ ends the body, anything else must be white space and a line end.
afterBoundary :: Reader -> IO Bool
afterBoundary r = do
  b <- ensure r 2
  if BS.take 2 b == "--"
    then writeIORef r.buffer (BS.drop 2 b) >> writeIORef r.state Done >> pure False
    else do
      rest <- line r limit
      if BC.all (`elem` (" \t" :: String)) rest then pure True else throwIO (Malformed "content after a boundary")

-- | The next part, or 'Nothing' after the closing boundary. The rest of the current part is skipped.
nextPart :: Reader -> IO (Maybe Part)
nextPart r = do
  st <- readIORef r.state
  case st of
    Done -> pure Nothing
    Start -> do
      -- The first boundary may start the body, with no line end before it.
      b <- ensure r (BS.length r.delimiter)
      writeIORef r.buffer ("\r\n" <> b)
      skipPast r r.delimiter limit
      open
    InPart -> drain >> open
    Between -> open
  where
    drain = do
      c <- partBody r
      if BS.null c then pure () else drain
    open = do
      more <- afterBoundary r
      if not more
        then pure Nothing
        else do
          hs <- headerLines (0 :: Int) limit []
          writeIORef r.state InPart
          pure (Just (Part hs (partBody r)))
    headerLines count budget acc = do
      l <- line r budget
      if BS.null l
        then pure (reverse acc)
        else do
          when (count >= 8) (throwIO (Malformed "too many headers"))
          let (k, v) = BC.break (== ':') l
          when (BS.null v || BS.null (BC.strip k)) (throwIO (Malformed "a header line has no name"))
          headerLines (count + 1) (budget - BS.length l - 2) ((CI.mk (BC.strip k), BC.strip (BS.drop 1 v)) : acc)

-- | The next piece of the current part, empty once its delimiter is reached.
partBody :: Reader -> IO ByteString
partBody r = do
  st <- readIORef r.state
  if st /= InPart
    then pure BS.empty
    else do
      b <- readIORef r.buffer
      let d = r.delimiter
          (before, rest) = BS.breakSubstring d b
      if
        | not (BS.null rest) ->
            if BS.null before
              then do
                writeIORef r.buffer (BS.drop (BS.length d) rest)
                writeIORef r.state Between
                pure BS.empty
              else writeIORef r.buffer rest >> pure before
        | BS.length b > BS.length d -> do
            -- Keep a tail that could be the start of the delimiter.
            let safe = BS.length b - BS.length d + 1
            writeIORef r.buffer (BS.drop safe b)
            pure (BS.take safe b)
        | otherwise -> do
            more <- fill r
            if more then partBody r else throwIO (Malformed "unexpected end of the body")
