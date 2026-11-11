namespace Marola.Server

open System
open System.Net
open System.Threading.Tasks
open Microsoft.AspNetCore.Http
open Microsoft.Extensions.Primitives

/// Headers, the client address and the rate-limit key: what every response and every request shares.
module Security =

    /// Sent on every response, built once. The CSP is the page's (`Csp.fs`) plus `form-action`, which a
    /// `<meta>` policy cannot carry for a form posted to the server.
    let responseHeaders: (string * StringValues) array =
        [| "Content-Security-Policy", StringValues(Marola.Csp.policy () + "; form-action 'self'")
           "Strict-Transport-Security", StringValues "max-age=63072000; includeSubDomains"
           "X-Content-Type-Options", StringValues "nosniff"
           "Referrer-Policy", StringValues "strict-origin-when-cross-origin"
           "Permissions-Policy", StringValues "geolocation=(self), camera=(), microphone=(), payment=(), usb=()"
           "Cross-Origin-Opener-Policy", StringValues "same-origin"
           "Cross-Origin-Resource-Policy", StringValues "same-origin" |]

    // Set in OnStarting, not before `next`: the exception handler clears the headers of a failed
    // response, and this callback runs after it, when the real response starts.
    let private apply =
        Func<obj, Task>(fun state ->
            let headers = (state :?> HttpContext).Response.Headers

            // A route may set its own CSP (the PDF route does: it must replace the page's, not add to it).
            for (name, value) in responseHeaders do
                if name <> "Content-Security-Policy" || not (headers.ContainsKey name) then
                    headers[name] <- value

            headers.Remove "Server" |> ignore
            headers.Remove "X-Powered-By" |> ignore
            Task.CompletedTask)

    let middleware =
        Func<HttpContext, RequestDelegate, Task>(fun ctx next ->
            ctx.Response.OnStarting(apply, ctx)
            next.Invoke ctx)

    /// The address of the client for the rate limit, never logged. `X-Forwarded-For` counts only when
    /// the peer is the loopback (nginx on the same host): anyone else could write that header. nginx must
    /// replace the header with `$remote_addr`; the last entry is used, the one a proxy appended.
    let clientAddress (peer: IPAddress) (forwardedFor: string) : IPAddress =
        let peer = if isNull peer then IPAddress.Loopback else peer
        let peer = if peer.IsIPv4MappedToIPv6 then peer.MapToIPv4() else peer

        if IPAddress.IsLoopback peer && not (String.IsNullOrWhiteSpace forwardedFor) then
            let last = forwardedFor.Substring(forwardedFor.LastIndexOf ',' + 1).Trim()

            match IPAddress.TryParse last with
            | true, address ->
                if address.IsIPv4MappedToIPv6 then
                    address.MapToIPv4()
                else
                    address
            | _ -> peer
        else
            peer

    /// The partition of the rate limiter: an IPv4 address, or the /64 of an IPv6 one (a single host
    /// owns a whole /64, so per-address limits would be free to dodge).
    let rateKey (address: IPAddress) : string =
        if address.AddressFamily = Sockets.AddressFamily.InterNetworkV6 then
            let bytes = address.GetAddressBytes()
            Array.fill bytes 8 8 0uy
            IPAddress(bytes).ToString()
        else
            address.ToString()

    let requestKey (ctx: HttpContext) : string =
        clientAddress ctx.Connection.RemoteIpAddress (ctx.Request.Headers["X-Forwarded-For"].ToString())
        |> rateKey
