# marola-server

The site's server: warp and wai, SQLite through sqlite-simple. It serves `dist/` and the board data,
sends the security headers and CSP, takes the contact form, the GitHub login and the study API and
pages, and runs the board's commands ([ADR 0005](../../docs/adr/0005-elm-and-haskell.md),
[docs/5-hosting.md](../../docs/5-hosting.md)).

## Build and test

GHC 9.6.6 and cabal 3.12. The cabal project is the repo's root `cabal.project` (this package and
`back/pages`), and the versions are pinned in the root `cabal.project.freeze`. Run these from the root:

```bash
cabal build exe:marola-server
cabal test marola-server
cabal list-bin marola-server        # the path of the executable
```

The smoke test runs the whole site against a built page, using node and the fake GitHub in
`scripts/fake_github.mjs`:

```bash
MAROLA_SERVER_BIN="$(cabal list-bin marola-server)" SMOKE_STATIC=<built page> scripts/server_smoke.sh
```

## Run

```bash
marola-server                        # serves on 127.0.0.1:${MAROLA_PORT:-8080}
marola-server inbox [--delete <id>]  # the contact messages
marola-server csp                    # the Content-Security-Policy header, as scripts/site_build.sh writes it to csp.txt
marola-server studies list|hide|unhide …, marola-server reports [close <id> --note …]
MAROLA_DEV=1 marola-server dev-account --login <name> --age-days <n>
```

| Variable | Meaning |
|---|---|
| `MAROLA_PORT` | the loopback port (8080) |
| `MAROLA_STATIC` | the built page (`dist`, written by `scripts/site_build.sh`) |
| `MAROLA_DATA` | the board data, served under `/data/` before the page's own |
| `MAROLA_DB` | the SQLite file |
| `MAROLA_STUDIES`, `MAROLA_STUDIES_QUOTA` | where the PDFs go, and their total size |
| `MAROLA_GITHUB_CLIENT_ID`, `MAROLA_GITHUB_CLIENT_SECRET_FILE` | the GitHub login; without them `/auth/github/*` answers 503 |
| `MAROLA_DEV` | `1` on a developer's machine only: plain-HTTP cookies, GitHub URLs from `MAROLA_GITHUB_BASE` and `MAROLA_GITHUB_API_BASE`, and `dev-account` |

## Behaviour worth knowing

- A rate-limit window starts at a client's first request, not on a timer.
- A log line is one JSON object: method, path, status, time. The server writes no startup line.
- Warp strips the body of a HEAD response, and the request time is measured until the response is
  ready, not until it is sent.
- A repeated query key takes its first value. The multipart reader and the route matcher are
  written for this server and tested on the requests `cabal test marola-server` and
  `scripts/server_smoke.sh` send.
