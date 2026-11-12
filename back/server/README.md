# marola-server

The Haskell port of the F# server in `app/Server`: warp and wai, SQLite through sqlite-simple. It
keeps the F# contract: the same routes, environment variables, headers and CSP, rate limits,
SQLite schema (`PRAGMA user_version`), PDF intake and board commands. A database written by one
server is read by the other.

## Build and test

GHC 9.6.6 and cabal 3.12. Versions are pinned in `cabal.project.freeze`. Run these from this folder:

```bash
cabal build exe:marola-server
cabal test
cabal list-bin marola-server        # the path of the executable
```

The smoke test runs the whole site against a built page, using node and the fake GitHub in
`scripts/fake_github.mjs`:

```bash
MAROLA_SERVER_BIN="$(cabal list-bin marola-server)" SMOKE_STATIC=<built page> bash ../../scripts/server_smoke.sh
```

## Run

```bash
marola-server                        # serves on 127.0.0.1:${MAROLA_PORT:-8080}
marola-server inbox [--delete <id>]  # the contact messages
marola-server studies list|hide|unhide …, marola-server reports [close <id> --note …]
MAROLA_DEV=1 marola-server dev-account --login <name> --age-days <n>
```

| Variable | Meaning |
|---|---|
| `MAROLA_PORT` | the loopback port (8080) |
| `MAROLA_STATIC` | the built page (`app/dist`, else `dist`) |
| `MAROLA_DATA` | the board data, served under `/data/` before the page's own |
| `MAROLA_DB` | the SQLite file |
| `MAROLA_STUDIES`, `MAROLA_STUDIES_QUOTA` | where the PDFs go, and their total size |
| `MAROLA_GITHUB_CLIENT_ID`, `MAROLA_GITHUB_CLIENT_SECRET_FILE` | the GitHub login; without them `/auth/github/*` answers 503 |
| `MAROLA_DEV` | `1` on a developer's machine only: plain-HTTP cookies, GitHub URLs from `MAROLA_GITHUB_BASE` and `MAROLA_GITHUB_API_BASE`, and `dev-account` |

## Where it differs from the F# server

- The rate-limit windows start at a client's first request. .NET's fixed windows start on a timer.
- A log line has no `State` object, and the server writes no startup line.
- Warp strips the body of a HEAD response, not the app, and the request time is measured until the
  response is ready, not until it is sent.
- The gzip bytes differ from .NET's; brotli and the choice between the two are the same.
- A repeated query key takes its first value. The multipart reader and the route matcher are
  written for this server, and they follow what ASP.NET does only on the requests the tests send.
