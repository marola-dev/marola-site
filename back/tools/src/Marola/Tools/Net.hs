-- | A free local port, and waiting for a server to answer.
module Marola.Tools.Net (freePort, waitHttp) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, bracket, try)
import Network.HTTP.Client qualified as H
import Network.Socket

-- | A port the kernel just handed out on 127.0.0.1, closed again for the caller to bind.
freePort :: IO Int
freePort = bracket (socket AF_INET Stream defaultProtocol) close $ \s -> do
  bind s (SockAddrInet 0 (tupleToHostAddress (127, 0, 0, 1)))
  fromIntegral <$> socketPort s

-- | True once a GET of the URL gets any answer, within the given number of 200 ms tries.
waitHttp :: H.Manager -> String -> Int -> IO Bool
waitHttp manager url tries
  | tries <= 0 = pure False
  | otherwise = do
      req <- H.parseRequest url
      r <- try (H.httpNoBody req manager) :: IO (Either SomeException (H.Response ()))
      case r of
        Right _ -> pure True
        Left _ -> threadDelay 200000 >> waitHttp manager url (tries - 1)
