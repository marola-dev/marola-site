-- | Headers, the client address and the rate-limit key: what every response and every request shares.
module Marola.Server.Security
  ( responseHeaders
  , contentSecurityPolicy
  , addHeaders
  , clientAddress
  , rateKey
  , requestKey
  , peerAddress
  )
where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BC
import Data.CaseInsensitive qualified as CI
import Data.IP (IP (..), fromHostAddress, fromHostAddress6, fromIPv4, fromIPv6b, toIPv4, toIPv6b)
import Data.Text.Encoding qualified as TE
import Marola.Csp qualified as Csp
import Network.HTTP.Types (Header, HeaderName)
import Network.Socket (SockAddr (..))
import Network.Wai (Request, remoteHost, requestHeaders)
import Text.Read (readMaybe)

-- | The CSP is the page's (Marola.Csp) plus @form-action@, which a @<meta>@ policy cannot carry for
-- a form posted to the server.
contentSecurityPolicy :: ByteString
contentSecurityPolicy = TE.encodeUtf8 Csp.policy <> "; form-action 'self'"

-- | Sent on every response.
responseHeaders :: [Header]
responseHeaders =
  [ ("Content-Security-Policy", contentSecurityPolicy)
  , ("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
  , ("X-Content-Type-Options", "nosniff")
  , ("Referrer-Policy", "strict-origin-when-cross-origin")
  , ("Permissions-Policy", "geolocation=(self), camera=(), microphone=(), payment=(), usb=()")
  , ("Cross-Origin-Opener-Policy", "same-origin")
  , ("Cross-Origin-Resource-Policy", "same-origin")
  ]

-- | A route may set its own CSP (the PDF route does: it must replace the page's, not add to it); every
-- other header of the list wins over what a route set. No @Server@, no @X-Powered-By@.
addHeaders :: [Header] -> [Header]
addHeaders hs =
  let names = map fst responseHeaders :: [HeaderName]
      ownCsp = [h | h@(n, _) <- hs, n == "Content-Security-Policy"]
      kept = [h | h@(n, _) <- hs, n `notElem` names, n `notElem` ["Server", "X-Powered-By"]]
      ours = [h | h@(n, _) <- responseHeaders, n /= "Content-Security-Policy" || null ownCsp]
   in ours <> ownCsp <> kept

unmap :: IP -> IP
unmap = \case
  IPv6 a | take 12 (fromIPv6b a) == replicate 10 0 <> [255, 255] -> IPv4 (toIPv4 (drop 12 (fromIPv6b a)))
  ip -> ip

isLoopback :: IP -> Bool
isLoopback = \case
  IPv4 a -> take 1 (fromIPv4 a) == [127]
  IPv6 a -> fromIPv6b a == replicate 15 0 <> [1]

peerAddress :: SockAddr -> IP
peerAddress = \case
  SockAddrInet _ h -> IPv4 (fromHostAddress h)
  SockAddrInet6 _ _ h _ -> unmap (IPv6 (fromHostAddress6 h))
  SockAddrUnix _ -> IPv4 (toIPv4 [127, 0, 0, 1])

-- | The address of the client for the rate limit, never logged. @X-Forwarded-For@ counts only when
-- the peer is the loopback (nginx on the same host): anyone else could write that header. nginx must
-- replace the header with @$remote_addr@; the last entry is used, the one a proxy appended.
clientAddress :: IP -> ByteString -> IP
clientAddress peer forwarded =
  let peer' = unmap peer
      lastEntry = BC.strip (snd (BC.spanEnd (/= ',') forwarded))
   in if isLoopback peer' && not (BC.null (BC.strip forwarded))
        then maybe peer' unmap (readMaybe (BC.unpack lastEntry))
        else peer'

-- | The partition of the rate limiter: an IPv4 address, or the /64 of an IPv6 one (a single host
-- owns a whole /64, so per-address limits would be free to dodge).
rateKey :: IP -> String
rateKey = \case
  IPv6 a -> show (IPv6 (toIPv6b (take 8 (fromIPv6b a) <> replicate 8 0)))
  ip -> show ip

requestKey :: Request -> String
requestKey req =
  let xff = maybe "" id (lookup (CI.mk "X-Forwarded-For") (requestHeaders req))
   in rateKey (clientAddress (peerAddress (remoteHost req)) xff)
