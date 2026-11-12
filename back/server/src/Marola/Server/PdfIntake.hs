-- | Takes a PDF from a stream: counts it, hashes it, checks it and, unless it is a dry run, writes it
-- to a temp file. The bytes are never held in memory as a whole. Storing under the hash is 'commit'.
-- ADR 0004 and docs/5-hosting.md give the rules.
module Marola.Server.PdfIntake
  ( maxBytes
  , forbiddenNames
  , Received (..)
  , receive
  , receiveBytes
  , pathOf
  , used
  , fitsQuota
  , commit
  , discard
  -- * The scanners, for the tests
  , scanNames
  , dictionaryOk
  , headerOk
  )
where

import Codec.Compression.Zlib.Internal qualified as Z
import Control.Exception (SomeException, onException, try)
import Control.Monad (forM_, unless)
import Crypto.Hash (Context, Digest, SHA256)
import Crypto.Hash qualified as H
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Unsafe qualified as BU
import Data.Char (isDigit)
import Data.IORef
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word8)
import Marola.Server.Config (Config (..))
import Marola.Server.StudyStore (hexLower, randomBytes)
import Marola.Study (FieldError (..), validSha256)
import System.Directory
import System.FilePath ((</>))
import System.IO hiding (latin1)
import System.Posix.Files (setFileMode)
import System.Posix.Types (FileMode)
import System.Posix.IO qualified as P
import Text.ParserCombinators.ReadP qualified as R

maxBytes :: Int64
maxBytes = 20 * 1024 * 1024

-- | @%%EOF@ and @startxref@ must sit in the last 1024 bytes: a file cut short does not.
tailSize :: Int
tailSize = 1024

-- | The names of active content. Every byte of the file is scanned for a PDF name (a @/@ and the
-- regular characters after it, @#xx@ decoded, so @/J#53@ is @/JS@), in streams too. @/OpenAction@
-- is refused only when its value is not a destination array, an indirect reference or null. The
-- inflated bytes of a compressed object stream are scanned the same way; other streams are not.
forbiddenNames :: [ByteString]
forbiddenNames = ["Launch", "JavaScript", "JS", "EmbeddedFile"]

isSpace8 :: Word8 -> Bool
isSpace8 b = b == 0 || b == 9 || b == 10 || b == 12 || b == 13 || b == 32

isDelimiter :: Word8 -> Bool
isDelimiter b = b `BS.elem` "()<>[]{}/%"

hexValue :: Word8 -> Int
hexValue b
  | b >= 48 && b <= 57 = fromIntegral b - 48
  | b >= 97 && b <= 102 = fromIntegral b - 87
  | b >= 65 && b <= 70 = fromIntegral b - 55
  | otherwise = -1

-- ---- the name scanner ----------------------------------------------------------------------------

-- | Reads names byte by byte, across chunk borders. The name bytes are kept reversed, at most 32.
data Names = Names
  { inName :: !Bool
  , len :: !Int
  , buf :: ![Word8]
  , pendingOpenAction :: !Bool
  , encrypted :: !Bool
  , found :: !(Maybe Text)
  }

names0 :: Names
names0 = Names False 0 [] False False Nothing

decoded :: Names -> ByteString
decoded s
  -- A name longer than the buffer is no name on the list; "" matches nothing.
  | s.len > 32 = ""
  | otherwise = BS.pack (go (reverse s.buf))
  where
    go (35 : a : b : rest) | hexValue a >= 0 && hexValue b >= 0 = fromIntegral (hexValue a * 16 + hexValue b) : go rest
    go (c : rest) = c : go rest
    go [] = []

-- | Ends the current name; the 'Bool' is true for @/ObjStm@, the object stream finder's start signal.
finishName :: Names -> (Names, Bool)
finishName s
  | not s.inName = (s, False)
  | otherwise =
      let n = decoded s
          s' = s {inName = False, len = 0, buf = []}
       in if
            | n `elem` forbiddenNames -> (s' {found = Just ("/" <> latin1 n)}, False)
            | n == "OpenAction" -> (s' {pendingOpenAction = True}, False)
            | n == "Encrypt" -> (s' {encrypted = True}, False)
            | n == "ObjStm" -> (s', True)
            | otherwise -> (s', False)

latin1 :: ByteString -> Text
latin1 = T.pack . BC.unpack

feedName :: Names -> Word8 -> (Names, Bool)
feedName s0 b
  | Just _ <- s0.found = (s0, False)
  | otherwise =
      let (s1, armed)
            | s0.inName =
                if isSpace8 b || isDelimiter b
                  then finishName s0
                  else (s0 {len = s0.len + 1, buf = if s0.len < 32 then b : s0.buf else s0.buf}, False)
            | otherwise = (s0, False)
          -- Not an else: the byte that ends a name is also the next byte after it.
          s2
            | s1.inName = s1
            | otherwise =
                let s' =
                      if s1.pendingOpenAction && not (isSpace8 b)
                        then
                          let ok = b == 91 || (b >= 48 && b <= 57) || b == 110
                           in s1 {pendingOpenAction = False, found = if ok then s1.found else Just "/OpenAction with an action"}
                        else s1
                 in if b == 47 then s' {inName = True, len = 0, buf = []} else s'
       in (s2, armed)

finishNames :: Names -> Names
finishNames s
  | Just _ <- s.found = s {pendingOpenAction = False}
  | otherwise = (fst (finishName s)) {pendingOpenAction = False}

-- | True when the scanner has nothing to do with a byte that is not @/@.
namesIdle :: Names -> Bool
namesIdle s = case s.found of
  Just _ -> True
  Nothing -> not s.inName && not s.pendingOpenAction

-- | Runs the name scan over a whole buffer: the first forbidden thing, and whether @/Encrypt@ was seen.
scanNames :: ByteString -> (Maybe Text, Bool)
scanNames bytes =
  let s = finishNames (fst (feedNames names0 bytes))
   in (s.found, s.encrypted)

-- | Feeds a chunk to the name scanner alone, skipping to the next @/@ while it is idle.
feedNames :: Names -> ByteString -> (Names, ())
feedNames s0 chunk = (go s0 0, ())
  where
    n = BS.length chunk
    go !s !i
      | i >= n = s
      | namesIdle s = case s.found of
          Just _ -> s
          Nothing -> maybe s (\j -> step s (i + j)) (BS.elemIndex 47 (BU.unsafeDrop i chunk))
      | otherwise = step s i
    -- The skip lands on the @/@ itself; feeding it is what leaves the idle state.
    step !s !i = go (fst (feedName s (BU.unsafeIndex chunk i))) (i + 1)

-- ---- the object stream finder --------------------------------------------------------------------

-- | Finds the compressed object streams while the file is read, without parsing PDF. A @/ObjStm@
-- name starts a search for the next @stream@ keyword within 600 bytes. The text from the last @<<@
-- before it must match a strict dictionary grammar ('dictionaryOk'), and the @<<@ must follow an
-- @N G obj@ that starts a line ('headerOk'). Anything else is a refusal: false positives cost less
-- than an exploit. A stream with @/Filter /FlateDecode@ records the offset of its first byte.
data Finder = Finder
  { head_ :: !ByteString
  , after :: ![Word8]
  -- ^ reversed
  , afterLen :: !Int
  , pending :: !Bool
  , skipping :: !Bool
  , offsets :: ![Int64]
  -- ^ reversed
  , count :: !Int
  , refusal :: !(Maybe Text)
  }

finder0 :: Finder
finder0 = Finder "" [] 0 False False [] 0 Nothing

finderIdle :: Finder -> Bool
finderIdle f = case f.refusal of
  Just _ -> True
  Nothing -> not f.pending && not f.skipping

ws :: Char -> Bool
ws c = c `elem` (" \t\r\n\f\0" :: String)

-- | @^<<(?:entry)*ws*>>ws*stream$@, the entries being /Type /ObjStm, /N int, /First int, /Length
-- int [int int R], /Extends int int R and /Filter /FlateDecode.
dictionaryOk :: String -> Bool
dictionaryOk s = any (null . snd) (R.readP_to_S grammar s)
  where
    ws0 = R.munch ws
    ws1 = R.munch1 ws
    int = R.munch1 isDigit
    key k = ws0 >> R.string k
    ref = ws1 >> int >> ws1 >> int >> ws1 >> R.char 'R'
    entry =
      R.choice
        [ key "/Type" >> ws0 >> R.string "/ObjStm" >> pure ()
        , key "/N" >> ws1 >> int >> pure ()
        , key "/First" >> ws1 >> int >> pure ()
        , key "/Length" >> ws1 >> int >> R.option () (ws1 >> int >> ws1 >> R.char 'R' >> pure ())
        , key "/Extends" >> ref >> pure ()
        , key "/Filter" >> ws0 >> R.string "/FlateDecode" >> pure ()
        ]
    grammar = do
      _ <- R.string "<<"
      _ <- R.many entry
      ws0 >> R.string ">>" >> ws0 >> R.string "stream" >> R.eof

-- | @[\r\n]ws*\d+ws+\d+ws+obj ws*$@ at the end of the text before the @<<@.
headerOk :: String -> Bool
headerOk before =
  let r = reverse before
      (_, r1) = span ws r
   in case r1 of
        'j' : 'b' : 'o' : r2 ->
          let (s1, r3) = span ws r2
              (d1, r4) = span isDigit r3
              (s2, r5) = span ws r4
              (d2, r6) = span isDigit r5
              (s3, _) = span ws r6
           in not (null s1) && not (null d1) && not (null s2) && not (null d2) && any (`elem` ("\r\n" :: String)) s3
        _ -> False

checkDict :: Finder -> Finder
checkDict f =
  let text = BC.unpack f.head_ <> map (toEnum . fromIntegral) (reverse f.after)
      starts = [i | (i, ('<', '<')) <- zip [0 :: Int ..] (zip text (drop 1 text))]
   in case starts of
        [] -> f {refusal = Just "an object stream has no dictionary the scan can read"}
        _ ->
          let start = last starts
              (before, dict) = splitAt start text
           in if not (headerOk before) || not ("/ObjStm" `T.isInfixOf` T.pack dict) || not (dictionaryOk dict)
                then f {refusal = Just "an object stream has a dictionary the scan cannot check"}
                else
                  if "/Filter" `T.isInfixOf` T.pack dict
                    then
                      if f.count >= 10000
                        then f {refusal = Just "the file has too many object streams to scan"}
                        else f {skipping = True}
                    else f

-- | One byte at absolute offset @pos@. @recent@ gives the last 1024 bytes up to and including it.
feedFinder :: Finder -> Int64 -> Word8 -> Bool -> ByteString -> Finder
feedFinder f0 pos b armed recent
  | Just _ <- f0.refusal = f0
  | otherwise =
      let f1
            | f0.skipping =
                if isSpace8 b then f0 else f0 {offsets = pos : f0.offsets, count = f0.count + 1, skipping = False}
            | f0.pending =
                let f = f0 {after = b : f0.after, afterLen = f0.afterLen + 1}
                 in if
                      | f.afterLen > 600 -> f {refusal = Just "an object stream has no stream keyword near its name", pending = False}
                      | f.afterLen >= 6 && take 6 f.after == reverse (BS.unpack "stream") -> checkDict f {pending = False}
                      | otherwise -> f
            | otherwise = f0
       in case f1.refusal of
            Just _ -> f1
            Nothing
              | armed && not f1.pending && not f1.skipping -> f1 {head_ = recent, after = [], afterLen = 0, pending = True}
              | otherwise -> f1

-- ---- the stream ----------------------------------------------------------------------------------

data Scan = Scan
  { names :: !Names
  , finder :: !Finder
  , position :: !Int64
  , previous :: !ByteString
  -- ^ The last 1024 bytes before the current chunk: the head of a dictionary and the tail of the file.
  }

feedChunk :: Scan -> ByteString -> Scan
feedChunk s0 chunk =
  let n = BS.length chunk
      recentAt i = let w = s0.previous <> BS.take (i + 1) chunk in BS.drop (BS.length w - tailSize) w
      go !ns !fd !i
        | i >= n = (ns, fd)
        | namesIdle ns && finderIdle fd = case ns.found of
            Just _ -> (ns, fd)
            Nothing -> maybe (ns, fd) (\j -> step ns fd (i + j)) (BS.elemIndex 47 (BU.unsafeDrop i chunk))
        | otherwise = step ns fd i
      step !ns !fd !i =
            let b = BU.unsafeIndex chunk i
                (ns', armed) = feedName ns b
                fd' = feedFinder fd (s0.position + fromIntegral i) b armed (if armed then recentAt i else "")
             in go ns' fd' (i + 1)
      (names', finder') = go s0.names s0.finder 0
      w = s0.previous <> chunk
   in Scan names' finder' (s0.position + fromIntegral n) (BS.drop (BS.length w - tailSize) w)

data Received = Received
  { sha256 :: Text
  , size :: Int64
  , temp :: Maybe FilePath
  -- ^ The temp file, or 'Nothing' on a dry run.
  }
  deriving (Show)

-- | A failure is a field error on @pdf@: @too_large@ (413), @not_pdf@, @truncated@,
-- @active_content@, @pdf_encrypted@ or @pdf_unscannable@ (400).
failWith :: Text -> Text -> FieldError
failWith code message = FieldError {field = "pdf", code = code, message = message}

activeContent :: Text -> FieldError
activeContent name = failWith "active_content" ("the file contains " <> name <> ", which marola does not host")

unscannable :: Text -> FieldError
unscannable why = failWith "pdf_unscannable" (why <> ", so marola cannot check it")

perStreamCap, perFileCap :: Int64
perStreamCap = 32 * 1024 * 1024
perFileCap = 128 * 1024 * 1024

-- | Inflates each object stream from the file in pieces and scans it; the output is never kept, and
-- the caps stop a zip bomb after 32 MB of one stream or 128 MB of the file.
scanObjStms :: Handle -> [Int64] -> IO (Maybe FieldError)
scanObjStms h = go 0
  where
    go _ [] = pure Nothing
    go total (offset : rest) = do
      hSeek h AbsoluteSeek (fromIntegral offset)
      r <- inflate total (Z.decompressIO Z.zlibFormat Z.defaultDecompressParams) names0 0
      case r of
        Left e -> pure (Just e)
        Right total' -> go total' rest
    inflate !total stream !scanner !sz = case stream of
      Z.DecompressInputRequired more -> do
        chunk <- BS.hGetSome h 65536
        -- An empty chunk tells zlib the input ended: the compressed data was cut short.
        next <- more chunk
        inflate total next scanner sz
      Z.DecompressOutputAvailable out next -> do
        let n = fromIntegral (BS.length out)
            sz' = sz + n
            total' = total + n
        if sz' > perStreamCap || total' > perFileCap
          then pure (Left (unscannable "an object stream inflates to more than the scan allows"))
          else do
            stream' <- next
            inflate total' stream' (fst (feedNames scanner out)) sz'
      Z.DecompressStreamEnd _ -> case (finishNames scanner).found of
        Just name -> pure (Left (activeContent name))
        Nothing -> pure (Right total)
      Z.DecompressStreamError Z.TruncatedInput -> case (finishNames scanner).found of
        Just name -> pure (Left (activeContent name))
        Nothing -> pure (Left (unscannable "an object stream is cut short"))
      Z.DecompressStreamError _ -> pure (Left (unscannable "an object stream does not inflate"))

incoming :: Config -> FilePath
incoming config = config.studies </> ".incoming"

ensureDirs :: Config -> IO ()
ensureDirs config = forM_ [config.studies, incoming config] $ \d -> do
  exists <- doesDirectoryExist d
  unless exists $ do
    createDirectoryIfMissing True d
    setFileMode d 0o750

-- | The path of a stored file, built from a hash that passed 'validSha256' and nothing else.
pathOf :: Config -> Text -> FilePath
pathOf config sha
  | validSha256 sha = config.studies </> (T.unpack sha <> ".pdf")
  | otherwise = error "pathOf: not a SHA-256"

-- | A new file, created exclusively with @mode@.
createNew :: FilePath -> FileMode -> IO Handle
createNew path mode = do
  fd <- P.openFd path P.ReadWrite P.defaultFileFlags {P.creat = Just mode, P.exclusive = True}
  setFileMode path mode
  h <- P.fdToHandle fd
  hSetBinaryMode h True
  pure h

-- | Streams the chunks @next@ returns (an empty one ends the input). @store = False@ is a dry run: it
-- stores nothing under @MAROLA_STUDIES@.
receive :: Config -> Bool -> IO ByteString -> IO (Either FieldError Received)
receive config store next = do
  token <- BC.unpack . hexLower <$> randomBytes 16
  -- The file is always written: the compressed object streams are inflated from it after the last
  -- byte is read. A dry run uses a private temp file, deleted at the end.
  path <-
    if store
      then ensureDirs config >> pure (incoming config </> token)
      else (</> ("marola-dry-" <> token)) <$> getTemporaryDirectory
  h <- createNew path (if store then 0o640 else 0o600)
  let cleanup = hClose h >> removeIfThere path
  flip onException cleanup $ do
    hashRef <- newIORef (H.hashInit :: Context SHA256)
    first5 <- newIORef BS.empty
    let loop !scan !total = do
          chunk <- next
          if BS.null chunk
            then pure (Right (scan, total))
            else do
              let total' = total + fromIntegral (BS.length chunk)
              if total' > maxBytes
                then pure (Left (failWith "too_large" ("the file is larger than " <> T.pack (show (maxBytes `div` 1048576)) <> " MB")))
                else do
                  modifyIORef' first5 (\f -> if BS.length f < 5 then f <> BS.take (5 - BS.length f) chunk else f)
                  modifyIORef' hashRef (`H.hashUpdate` chunk)
                  BS.hPut h chunk
                  loop (feedChunk scan chunk) total'
    r <- loop (Scan names0 finder0 0 "") 0
    outcome <- case r of
      Left e -> pure (Left e)
      Right (scan, total) -> do
        magic <- readIORef first5
        let ns = finishNames scan.names
            tailText = scan.previous
        if
          | magic /= "%PDF-" -> pure (Left (failWith "not_pdf" "the file does not start with %PDF-"))
          | not ("%%EOF" `BS.isInfixOf` tailText) || not ("startxref" `BS.isInfixOf` tailText) ->
              pure (Left (failWith "truncated" "the file has no startxref and %%EOF at its end: it looks cut short"))
          | Just name <- ns.found -> pure (Left (activeContent name))
          | ns.encrypted -> pure (Left (failWith "pdf_encrypted" "the file is encrypted, so marola cannot check what it contains"))
          | Just why <- scan.finder.refusal -> pure (Left (unscannable why))
          | otherwise -> do
              hFlush h
              f <- scanObjStms h (reverse scan.finder.offsets)
              case f of
                Just e -> pure (Left e)
                Nothing -> do
                  digest <- readIORef hashRef
                  pure (Right (T.pack (show (H.hashFinalize digest :: Digest SHA256)), total))
    hClose h
    case outcome of
      Left e -> removeIfThere path >> pure (Left e)
      Right (sha, total) -> do
        unless store (removeIfThere path)
        pure (Right Received {sha256 = sha, size = total, temp = if store then Just path else Nothing})

-- | 'receive' over bytes already in memory, for the tests.
receiveBytes :: Config -> Bool -> ByteString -> IO (Either FieldError Received)
receiveBytes config store bytes = do
  ref <- newIORef (chunks bytes)
  receive config store $ atomicModifyIORef' ref $ \case
    c : cs -> (cs, c)
    [] -> ([], BS.empty)
  where
    chunks b
      | BS.null b = []
      | otherwise = let (x, y) = BS.splitAt 65536 b in x : chunks y

removeIfThere :: FilePath -> IO ()
removeIfThere p = do
  r <- try (removeFile p) :: IO (Either SomeException ())
  either (const (pure ())) pure r

-- | Bytes the stored PDFs take now.
used :: Config -> IO Int64
used config = do
  exists <- doesDirectoryExist config.studies
  if not exists
    then pure 0
    else do
      entries <- listDirectory config.studies
      sizes <- mapM (\e -> do
        let p = config.studies </> e
        isFile <- doesFileExist p
        if isFile && ".pdf" `T.isSuffixOf` T.pack e then fromIntegral <$> getFileSize p else pure 0) entries
      pure (sum sizes)

-- | True when storing a file of this hash and size would pass the quota. A file already stored costs nothing.
fitsQuota :: Config -> Received -> IO Bool
fitsQuota config r = do
  there <- doesFileExist (pathOf config r.sha256)
  if there then pure True else (\u -> u + r.size <= config.studiesQuota) <$> used config

-- | Moves the temp file to @<sha256>.pdf@. The hash names the file, so the same bytes are written once.
commit :: Config -> Received -> IO ()
commit config r = case r.temp of
  Nothing -> pure ()
  Just t -> do
    let final = pathOf config r.sha256
    there <- doesFileExist final
    if there then removeFile t else renameFile t final

discard :: Received -> IO ()
discard r = maybe (pure ()) removeFile r.temp
