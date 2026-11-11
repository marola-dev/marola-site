# Hosting

The .NET server (`app/Server`, [ADR 0002](adr/0002-dotnet-server.md)) runs on piabrota2 (KVM 4)
behind nginx at `marola.piabrota.art`. Kestrel listens on `127.0.0.1` only. nginx ends TLS and sends
the requests on.

## Run it

```bash
just app-build --fixtures      # the page into app/dist (a deploy has its own data folder)
just server-run                # development: http://127.0.0.1:8080
just server-build              # publish into app/Server/out (framework-dependent, Release)
dotnet app/Server/out/marola-server.dll          # what a host runs
dotnet app/Server/out/marola-server.dll inbox    # the contact messages
```

The host needs the ASP.NET Core 10 runtime. The published folder holds the native SQLite library
under `runtimes/linux-x64/native/`, from the NuGet package.

## Build with Nix

`nix/package.nix` builds the whole site as one package: the server, the static pages and the Fable
client. The build has no network. The NuGet packages come from `nix/deps.json` (a fixed hash for each),
Fable and Node from nixpkgs, and MEMBERS.md from `site/members/` (pinned by blob id, see
[the development guide](3-development.md)). `flake.nix` exposes it as `packages.default` and as
`checks.package`.

```bash
just nix-build        # nix build .#default: result/bin/marola-server, result/share/marola/dist
just package-smoke    # starts result/bin/marola-server on a free port, checks / /about.html /en/studies /api/v1/skill.md
just nix-deps         # rewrites nix/deps.json after a change to any fsproj (needs the network)
```

The package holds:

- `bin/marola-server`: a wrapper that sets `DOTNET_ROOT`, the ICU library path and the runtime's `PATH`. It sets no
  secret and no `MAROLA_*` variable. The unit needs no `dotnet` of its own. The same binary runs the commands
  (`inbox`, `studies`, `reports`).
- `share/marola/dist`: the static site, the same tree as `just app-build` writes into `app/dist` (without
  `app/fable_modules/project_cracked.json`, Fable's cache, which holds the random name of the build's temp folder).
  `MAROLA_STATIC` points here.
- `lib/marola-site`: the published server (Release, framework-dependent, with `libe_sqlite3.so`).

There is no `data-seed`. `MAROLA_DATA` is the board data folder, `<area>/latest.json` and the boards, which the board
pipeline writes; the server reads `/data/<x>` there first and then under `dist/data` (`areas.json` and `trails/`,
which the package already holds). An empty or missing `MAROLA_DATA` is valid: the boards answer 404 until the
pipeline writes them.

**What piabrota/nix-os needs.**

1. An input for the source. With `flake = false` it takes no second lockfile (the devkit input of `flake.nix`
   stays out): `marola-site = { url = "github:marola-dev/marola-site/<commit>"; flake = false; };`. Then
   `pkgs.callPackage "${inputs.marola-site}/nix/package.nix" { }` gives the package, built with the nix-os nixpkgs.
   That nixpkgs must have `buildDotnetModule`, `dotnetCorePackages.sdk_10_0` and `aspnetcore_10_0`, `fable` and
   `nodejs`. The package built with nixpkgs `f4a03c00` (Fable 5.26.0, .NET SDK 10.0.403) and with the nix-os pin
   `02c087f3` of 2026-11-11 (Fable 5.20.0, .NET SDK 10.0.401); only the first one ran `just package-smoke`.
2. The unit, with these variables: `MAROLA_PORT`, `MAROLA_STATIC=<package>/share/marola/dist`, `MAROLA_DATA`,
   `MAROLA_DB`, `MAROLA_STUDIES`, `MAROLA_GITHUB_CLIENT_ID` (see [Variables](#variables)). Never set `MAROLA_DEV`.
3. A state directory (`StateDirectory=marola`) for the database, `csrf.key` and the studies. The package is
   read-only in the store; only the state directory is writable.
4. A secret file for the GitHub client secret, passed with `LoadCredential=` and named by
   `MAROLA_GITHUB_CLIENT_SECRET_FILE=%d/github-client-secret` ([The GitHub login](#the-github-login)). The secret
   stays out of the Nix store and out of the environment.
5. nginx that **replaces** `X-Forwarded-For` (`$remote_addr`, not `$proxy_add_x_forwarded_for`) and sends
   `Host $host` ([nginx](#nginx)).
6. `MemoryMax=256M`. The resident set of the package's server was 91 MB after the start and four requests
   (`just package-smoke`, 2026-11-11), so the limit is 2.8 times that. Nobody measured it under load or
   during a 20 MB upload; read `MemoryPeak` after the first weeks.
7. A backup of `marola.db`, `csrf.key` and `MAROLA_STUDIES` together ([The studies and their backup](#the-studies-and-their-backup)).

Size: the package is 11 MB; its closure is 214 MiB, of which the ASP.NET Core runtime is 202 MiB (ICU 87 MiB).

**What the build checks, and what it does not.** `nix build` runs with the sandbox on, so it cannot reach the
network. It does not check `packages.lock.json`: the nixpkgs restore passes `--runtime` (a locked restore fails with
NU1004), and Nix repacks each package without its signature (NU1403). `just app-test` and `just quality` check the lock
files. A package that is missing from `nix/deps.json` fails the build. Two builds on the same day give the same
bytes (`nix build --rebuild` finds no difference). `security.txt` holds the build day in its `Expires` line (the day
plus 364 days), so builds on two days differ in that one file.

## Variables

| Variable | Default | What |
|---|---|---|
| `MAROLA_PORT` | `8080` | The port on `127.0.0.1`. The server never listens on another address. |
| `MAROLA_STATIC` | `app/dist` | The built page. Served at `/`. Read-only. |
| `MAROLA_DATA` | `data` | The board data. `/data/<x>` is read here first, then under `MAROLA_STATIC`. Read-only. |
| `MAROLA_DB` | `data/marola.db` | The SQLite file: the contact messages, and the accounts, API keys, studies and reports of [ADR 0004](adr/0004-study-submission.md). The server creates it and its folder at start, and moves its tables to the current version (`PRAGMA user_version`). |
| `MAROLA_STUDIES` | `data/studies` | The PDFs of the studies, as `<sha256>.pdf`, mode 0640, in a folder of mode 0750 with a `.incoming` folder for uploads in progress. Outside `MAROLA_STATIC` and never served as a file tree. |
| `MAROLA_STUDIES_QUOTA` | `2147483648` (2 GiB) | The most bytes the stored PDFs may take. Past it, a new file gets 507. A wrong number stops the start with exit code 2. |
| `MAROLA_GITHUB_CLIENT_ID` | unset | The client id of the GitHub OAuth app. Public. |
| `MAROLA_GITHUB_CLIENT_SECRET_FILE` | unset | A path to the file that holds the client secret. The secret is read from that file at each login, never from an environment variable, and never logged. Without the id and the file, `/auth/github/login` answers 503 "login is not configured" and the rest of the site works. |
| `MAROLA_DEV` | unset | Only the value `1` enables it: the command `dev-account`, cookies without `Secure` and the `__Host-` prefix (plain HTTP), and `MAROLA_GITHUB_BASE` and `MAROLA_GITHUB_API_BASE` (a fake GitHub for tests). Never set it in the unit. |

A relative path counts from the working directory of the process. Use absolute paths on a host.
A wrong `MAROLA_PORT` or `MAROLA_STUDIES_QUOTA` stops the start with exit code 2.

## What the server does

- Serves files from the two roots only. A hidden file, a folder, a `..`, a backslash, an encoded
  slash, a NUL byte or an empty segment (`//`) gets 404. `/contact` finds `contact.html` when the
  page has one.
- Sends the security headers of [ADR 0002](adr/0002-dotnet-server.md) on every response that
  reaches the middleware, an error or a 429 included.
- Answers an exception with a plain 500 page.
- Refuses a body over 1 MB (413), except on `POST /api/v1/studies`, whose limit is 21 MB, and a client over its rate limit (429, with `Retry-After`): 300
  requests a minute, and 10 POST requests in 10 minutes.
- Sends a path that matches no file the 404 page (`404.html`, or `en/404.html` below `/en/`) with status 404.
- Takes `POST /contact` and `POST /en/contact` (`email`, `message`, honeypot `website`) and stores it in SQLite.
  It answers 303 to `/contact-sent.html`, or `/en/contact-sent.html` for the English route.
- Logs one JSON line for each request (method, path, status, time). No address, no query, no body.
- Takes the study API of [ADR 0004](adr/0004-study-submission.md): `POST /api/v1/studies` (an API key, `?dry_run=1`),
  `GET /api/v1/studies`, `GET /api/v1/studies/<id>`, `GET /api/v1/skill.md` and `GET /studies/<id>.pdf`. The upload
  is streamed to `MAROLA_STUDIES/.incoming`, hashed, checked and moved to `<sha256>.pdf`. It logs the study id and the
  account id, and never the title, the text, the file name or an address.

## The studies and their backup

Size the disk for `MAROLA_STUDIES_QUOTA` (2 GiB by default) plus the database. A study is a row in `marola.db`
and a file in `MAROLA_STUDIES`; back both up together, or a row can name a file that the copy lacks. Take the
database copy first and the folder second: a file without a row is harmless, a row without a file is not.

```bash
sqlite3 /var/lib/marola/marola.db ".backup '/var/backups/marola/marola-$(date +%F).db'"
rsync -a /var/lib/marola/studies/ /var/backups/marola/studies/
```

Files are named by their SHA-256, so `rsync` copies each one once. Delete nothing under `.incoming` while the
server runs; a file there older than a day is a failed upload and is safe to remove. A study that the board hides
keeps its file on disk (the tombstone keeps the hash). The board deletes a file with `studies hide <id> --purge`
([the board runbook](6-board.md)), never by hand.

**A restore of a backup undoes a purge.** A backup taken before the purge still holds
the file and the old database row. After a restore, the file is back on disk and the row no longer says it was
purged, so a hidden study stays unserved but the file exists again. The board records every purge (the line that
the command prints: date, id, hash). After any restore, read that record and purge those studies again. Keep
backups only as long as you need them: a deleted file lives in every backup that is older than its purge.

## nginx

nginx must send the real client address in `X-Forwarded-For`, and it must **replace** the header,
not append to it. The server counts that header only when the peer is `127.0.0.1`, and it uses the
last entry. nginx must also send the public host in `Host`: the contact form checks `Origin` against
it, and a wrong `Host` makes every post fail with 403.

```nginx
server {
    listen 80;
    server_name marola.piabrota.art;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name marola.piabrota.art;

    # ssl_certificate and ssl_certificate_key: the host's own (ACME).

    # HSTS once: nginx sends it, and hides the copy of the server. nginx's own error pages get it too.
    proxy_hide_header Strict-Transport-Security;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

    # The server refuses more than 1 MB itself. The study upload has its own location below, with
    # a larger limit; do not raise this one.
    client_max_body_size 1m;

    # The study upload, by the API and by the web form: 21 MB (a 20 MB file and the form fields). The server streams the file to its
    # own folder, so nginx passes it through and does not buffer it to disk first.
    location ~ ^(/en)?/submit$|^/api/v1/studies$ {
        client_max_body_size 21m;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Without `X-Forwarded-For`, every visitor shares the rate-limit window of `127.0.0.1`.

## The GitHub login

The study form and the account page need a login with GitHub (the web flow, empty scope: the server reads only
the public profile: id, login and the date the account was made). The owner registers the OAuth app on GitHub;
an agent cannot do it.

1. In GitHub, Settings, Developer settings, OAuth Apps, make an app. Its callback URL is
   `https://marola.piabrota.art/auth/github/callback`. Ask for no scope.
2. Put the client id in `MAROLA_GITHUB_CLIENT_ID`.
3. Write the client secret to a file only root can read, for example `/etc/marola/github-client-secret` (mode 0600).
   The unit passes it with `LoadCredential=`; systemd puts a copy in `$CREDENTIALS_DIRECTORY`, which `%d` names in
   `MAROLA_GITHUB_CLIENT_SECRET_FILE`. The secret is never in an environment variable, a log or the repository.
4. Restart the unit. `/auth/github/login` redirects to GitHub, and the callback starts a session of 12 hours.

The cookies are `__Host-msess` and `__Host-mstate`, so the site must be served over HTTPS (nginx sends
`X-Forwarded-Proto`; the server always sets `Secure`). The server makes `csrf.key` next to `MAROLA_DB` at the first
start (mode 0600); back it up with the database, because a restart without it only invalidates open forms.
The upload location of nginx above covers `/submit` and `/en/submit`.

## systemd

Recommended settings for the unit. The server needs no write access except to its state folder.

```ini
[Service]
ExecStart=/usr/bin/dotnet /opt/marola/server/marola-server.dll
Environment=MAROLA_PORT=8080
Environment=MAROLA_STATIC=/opt/marola/dist
Environment=MAROLA_DATA=/opt/marola/data
Environment=MAROLA_DB=/var/lib/marola/marola.db
Environment=MAROLA_STUDIES=/var/lib/marola/studies
Environment=MAROLA_STUDIES_QUOTA=2147483648
Environment=MAROLA_GITHUB_CLIENT_ID=<the public client id>
Environment=MAROLA_GITHUB_CLIENT_SECRET_FILE=%d/github-client-secret
LoadCredential=github-client-secret:/etc/marola/github-client-secret
DynamicUser=yes
StateDirectory=marola
MemoryMax=256M
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes
PrivateTmp=yes
Restart=on-failure
```

`ProtectSystem=strict` makes the whole file system read-only for the server except
`StateDirectory`, so the page and the data are read-only by construction. The deploy writes
`/opt/marola/dist` and `/opt/marola/data` as another user. The target of `MemoryMax=256M` comes
from a measured start at 75 MB resident (`scripts/server_smoke.sh` fails above 100 MB). Nobody
measured the server under load yet; watch `MemoryPeak` after the first weeks.

A dry run and a real upload both write the upload to a file while it is read (decision 20 of [ADR 0004](adr/0004-study-submission.md)): the real one under
`MAROLA_STUDIES/.incoming`, the dry run in the unit's private `/tmp` (`PrivateTmp=yes`), deleted when the request ends. On a
host where `/tmp` is a memory file system, a 20 MB dry run counts against `MemoryMax` while it runs.

## The messages and their backup

Read the messages as root, with the unit's variables:

```bash
sudo env MAROLA_DB=/var/lib/marola/marola.db dotnet /opt/marola/server/marola-server.dll inbox
sudo env MAROLA_DB=/var/lib/marola/marola.db dotnet /opt/marola/server/marola-server.dll inbox --delete 12
```

Each message is personal data (an email and a text). Delete a message when the reply is sent and
nobody needs it.

Back up `marola.db` with SQLite's own copy, which is safe while the server runs:

```bash
sqlite3 /var/lib/marola/marola.db ".backup '/var/backups/marola/marola-$(date +%F).db'"
```

The database uses the default rollback journal, so no `-wal` file exists. Keep the backups as
private as the file itself.

## Rollback

Publish each build into its own folder (`/opt/marola/server-<commit>`) and point
`/opt/marola/server` at it with a symbolic link. To go back, point the link at the earlier folder
and restart the unit. The tables only grow: an older server ignores the study tables, and a newer one moves
the database to its version at start (`PRAGMA user_version`; see [ADR 0004](adr/0004-study-submission.md)). Do not
delete `MAROLA_STUDIES` on a rollback: the rows name those files. The page (`dist`) rolls back the same way.

## What the server does not cover

- A response that Kestrel writes before the middleware runs (a malformed request line, a NUL byte in
  the path) has no security headers. HSTS comes from nginx for these.
- The rate limit is in memory and resets on a restart.
- There is no limit on the size of the message table. Look at `inbox` from time to time.
- The rate limit of a key is in memory too. The limits of an account (one study in 10 minutes, 10 in a day) are
  counted from the studies table and survive a restart.
- The quota counts the files in `MAROLA_STUDIES`. The disk under it needs the quota plus the space of a running upload (21 MB).
