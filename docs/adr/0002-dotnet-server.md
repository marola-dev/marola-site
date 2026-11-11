# ADR-0002: A .NET server behind nginx

| | |
|---|---|
| **Status** | Proposed |
| **Date** | 2026-11-11 |

## Context

[ADR-0001](0001-fsharp-fable-maplibre-dynamic-hosting.md) decided to run a .NET server on piabrota2
(a KVM 4) at `marola.piabrota.art`, in place of static hosting. `scripts/serve.mjs` served `app/dist`
for development only. It had no rate limit, no error page and no way to take a form.

The contact form posted to `formsubmit.co`, a third party that received every message. The map
needs a server for the pages and the data, for the contact form and, in a later run, for the study
submission.

## Decision

1. Write `app/Server` as an ASP.NET Core minimal API in F# (`Microsoft.NET.Sdk.Web`, .NET 10).
   Use no Giraffe, no MVC and no Razor. A small set of routes needs none of them, and each one
   would be one more package to lock and to audit.
2. Let Kestrel listen on `127.0.0.1:$MAROLA_PORT` only (default 8080), with no TLS. nginx faces the
   world, ends TLS and sends the requests on. [The hosting page](../5-hosting.md) has the nginx block.
3. Serve files from two roots only, with no directory listing: `MAROLA_STATIC` (`app/dist`) and
   `MAROLA_DATA` (the board data, under `/data/`). `Files.segments` accepts a path only if every
   segment is made of letters, digits, `.`, `-` and `_` and does not start with a dot. That rules
   out `..`, `\`, `%`, NUL, `:`, an empty segment (`//`) and every hidden file, so no encoding
   trick has to be recognised. A test sends about thirty hostile paths.
4. Send the security headers from one place, `Security.fs`, on every response that reaches the
   middleware: the CSP of `Csp.policy ()` plus `form-action 'self'`, HSTS, `nosniff`,
   `Referrer-Policy`, `Permissions-Policy`, and the two cross-origin policies. The code sets them in
   `OnStarting`, not before the next middleware, because the exception handler clears the headers of
   a failed response. The server sends no `Server` and no `X-Powered-By` header.
5. Compress text types (HTML, CSS, JavaScript, JSON, SVG, text, XML) with the built-in middleware,
   Brotli first and gzip second, at the fastest level.
6. Limit the rate with `Microsoft.AspNetCore.RateLimiting`, a fixed window for each client. The
   client is the peer address, or the last entry of `X-Forwarded-For` only when the peer is the
   loopback (nginx on the same host). Any other peer could write that header. An IPv6 client counts
   as its /64. The general limit is 300 requests a minute. The `strict` policy for POST routes is
   10 requests in 10 minutes. A refused request gets 429 with `Retry-After`.
7. Answer an unhandled exception with a plain 500 page. The page has no stack trace and no detail.
   The exception goes to the log. Refuse a body over 1 MB. The study upload of a later run will set
   its own limit on its own route.
8. Log to the console, one JSON object for each line. The framework logs only warnings. The server
   writes one line for each request: method, path without the query, status and time. The log has no
   IP address, no query string and no request body (LGPD). A test sends an address, a query and a
   body, and checks that none of them reaches the log.
9. Take the contact form at `POST /contact`. Check the fields (email syntax, message of 10 to 4000
   characters, no control character other than tab and newline), store the message in SQLite
   (`messages`: `id`, `created_utc`, `email`, `body`) and answer 303 to `/contact-sent.html` ([ADR 0003](0003-pages-in-fsharp.md) adds the English route). The
   honeypot field `website` must be empty. A bot that fills it gets 200 and nothing is stored.
10. Protect the form against cross-site posts with a check of `Origin` against `Host`, and of
    `Referer` when `Origin` is absent. A browser sends `Origin` on a cross-site POST and a page
    cannot forge it. The page is static, so it cannot carry a per-visitor token, and a cookie token
    would need the server to rewrite the HTML. nginx must send `Host $host` for this to work.
11. Read the messages with the command line: `marola-server inbox` lists them and
    `marola-server inbox --delete <id>` removes one. The board runs it over ssh. The server has no
    web page for the inbox, so it has no login to attack.
12. Target `MemoryMax=256M` in systemd. The process starts at 75 MB resident (measured by
    `scripts/server_smoke.sh`, which fails above 100 MB). The project turns off the server GC,
    concurrent GC and tiered PGO.

## Packages

The framework gives Kestrel, the rate limiter, the compression and the logging. NuGet adds only
these, each pinned in `packages.lock.json` (restore in locked mode):

| Package | Why |
|---|---|
| `Microsoft.Data.Sqlite` 10.0.15 | The contact store. One file, transactions, no second process. |
| `SQLitePCLRaw.lib.e_sqlite3` 2.1.14 | The native SQLite library, from the NuGet bundle. The version that `Microsoft.Data.Sqlite` pulls (2.1.11) carries SQLite before 3.50.2 (CVE-2025-6965), and NuGet audit refuses it with NU1903 (the build treats warnings as errors). 2.1.14 carries SQLite 3.54.0. |
| `Microsoft.AspNetCore.TestHost` 10.0.0 | `app/Server.Tests` only: the real pipeline in memory. |

The server project references `app/Shared` for `Csp.policy ()`.

## Consequences

- Kestrel answers some requests itself, before the middleware: a malformed request line, or a NUL
  byte in the path (`/%00`, a 400). Those responses have no security headers. nginx can add
  `Strict-Transport-Security` to them (see the hosting page); the CSP and the other headers have
  nothing to protect on a body of a few words.
- The `.html` fallback makes a clean URL work: `GET /contact` finds `contact.html`, while
  `POST /contact` is the form route. The build writes `contact.html` ([ADR 0003](0003-pages-in-fsharp.md)).
- The rate limit lives in memory and resets on a restart. It limits a client, not a botnet: many
  addresses could still fill the message table. The hosting page says to look at `inbox` from time to
  time. The server has no cap on the table.
- Compression runs for each request, at the fastest level. The files are small. If the CPU shows
  it, the next step is to compress at build time.
- The static site at `marola.dev` (Cloudflare) has the same `contact.html`, now posted to
  `/contact`. That host has no such route. The form works only on a host that runs this server.
- `scripts/serve.mjs` is gone, with its development recipe. `just server-run` runs the page now.

## Alternatives

- Giraffe or Falco. They give a nicer F# route syntax and pull in more packages. The server has two
  route handlers.
- `UseStaticFiles` for the files. It does not reject dotfiles or odd segments by an allowlist, and
  the two-root lookup with the `/data/` priority needs a custom provider anyway.
- A cookie token (double submit) for the form. It needs the HTML to carry or fetch the token. The
  Origin check gives the same protection for a browser with no change to the page.
- Forward the messages by e-mail. It needs an SMTP account and a secret on the box. The `inbox`
  command needs neither.
- Keep FormSubmit. It hands every message to a third party.
