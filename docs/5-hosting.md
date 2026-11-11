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

## Variables

| Variable | Default | What |
|---|---|---|
| `MAROLA_PORT` | `8080` | The port on `127.0.0.1`. The server never listens on another address. |
| `MAROLA_STATIC` | `app/dist` | The built page. Served at `/`. Read-only. |
| `MAROLA_DATA` | `data` | The board data. `/data/<x>` is read here first, then under `MAROLA_STATIC`. Read-only. |
| `MAROLA_DB` | `data/marola.db` | The SQLite file of the contact messages. The server creates it and its folder at start. |

A relative path counts from the working directory of the process. Use absolute paths on a host.
A wrong `MAROLA_PORT` stops the start with exit code 2.

## What the server does

- Serves files from the two roots only. A hidden file, a folder, a `..`, a backslash, an encoded
  slash, a NUL byte or an empty segment (`//`) gets 404. `/contact` finds `contact.html` when the
  page has one.
- Sends the security headers of [ADR 0002](adr/0002-dotnet-server.md) on every response that
  reaches the middleware, an error or a 429 included.
- Answers an exception with a plain 500 page.
- Refuses a body over 1 MB (413) and a client over its rate limit (429, with `Retry-After`): 300
  requests a minute, and 10 POST requests in 10 minutes.
- Sends a path that matches no file the 404 page (`404.html`, or `en/404.html` below `/en/`) with status 404.
- Takes `POST /contact` and `POST /en/contact` (`email`, `message`, honeypot `website`) and stores it in SQLite.
  It answers 303 to `/contact-sent.html`, or `/en/contact-sent.html` for the English route.
- Logs one JSON line for each request (method, path, status, time). No address, no query, no body.

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

    # The server refuses more than 1 MB itself. A later upload route needs its own location with a
    # larger limit; do not raise this one.
    client_max_body_size 1m;

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

## systemd

Recommended settings for the unit. The server needs no write access except to its state folder.

```ini
[Service]
ExecStart=/usr/bin/dotnet /opt/marola/server/marola-server.dll
Environment=MAROLA_PORT=8080
Environment=MAROLA_STATIC=/opt/marola/dist
Environment=MAROLA_DATA=/opt/marola/data
Environment=MAROLA_DB=/var/lib/marola/marola.db
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
and restart the unit. The database needs no step: the server only runs `create table if not
exists`, and no release changes the table yet. The page (`dist`) rolls back the same way.

## What the server does not cover

- A response that Kestrel writes before the middleware runs (a malformed request line, a NUL byte in
  the path) has no security headers. HSTS comes from nginx for these.
- The rate limit is in memory and resets on a restart.
- There is no limit on the size of the message table. Look at `inbox` from time to time.
