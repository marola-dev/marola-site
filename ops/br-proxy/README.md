# The Brazilian proxy pool for INEA and INEMA (#4)

INEA (Rio's bathing-water bulletins) and INEMA (Bahia's) do not answer connections from outside
Brazil, and GitHub's runners are not in Brazil, so without help `site.yml`'s build gives Rio's and
Salvador's beaches "no data". This directory is the help: a pool of small password-protected
proxies on volunteers' machines in Brazil, each on a port the volunteer forwards on their router,
that the build sends those two agencies through, and nothing else. (An earlier design joined the
nodes in a tailnet; it was dropped because the SaaS trial ended with a 402, and a self-hosted
coordination server was one more always-on public service when nodes need a forwarded port anyway.)

The build depends on it, and fails closed. Its flight check runs before any board is built: when
no node passes a real request to INEA, the job stops with an `::error::` naming the nodes by host
and port. Nothing deploys, and marola.dev keeps serving the last deployed site.
While no node is healthy, that holds for **every** area, Florianópolis's forecast too. The repo
variable `BR_PROXY_REQUIRED=false` is the break glass: the build then goes on without the proxy
(Rio and Salvador water quality "no data"). Unset means required; set it only while the pool is
down, and delete it afterwards.

```
site.yml build job (GitHub runner)
  ├─ scripts/br-proxy-preflight.sh: the flight check, the first entry of MAROLA_BR_PROXY through
  │    which https://www.inea.rj.gov.br/ really answers (2xx/3xx), ~10 s per node, 60 s in all;
  │    none: exit 1, the job stops (unless BR_PROXY_REQUIRED=false)
  ├─ scripts/br-proxy.sh start: a tinyproxy on the runner's 127.0.0.1:8899 that sends the hosts in
  │    ./hosts through that node and everything else (Overpass, Open-Meteo) direct
  └─ the app image, with --network host and JDK_JAVA_OPTIONS pointing its JVM at 127.0.0.1:8899
        └─> pool node in Brazil, over the internet, Basic auth (./compose.yml: proxy/, ./hosts)
              └─> www.inea.rj.gov.br / balneabilidade.inema.ba.gov.br
```

| File | What it is |
|---|---|
| `hosts` | The Brazil-only hosts the runner routes through the pool, and the node's allowlist too (exact names, nothing else) |
| `proxy/` | The node's proxy: our own Rust binary, std only ([ADR-0002](../../docs/adr/0002-rust-br-proxy-node.md)). It answers 407 without the password (before anything else), tunnels `CONNECT` to port 443 only, forwards plain HTTP to port 80 only, and answers 403 to every other host or port; off loopback it refuses to start without a password of 16+ characters; `cargo test` covers each refusal |
| `compose.yml`, `Dockerfile` | The node: the proxy alone, published on `BR_PROXY_PORT`, read-only and without capabilities; the Dockerfile builds and tests the proxy, pinned by digest |
| `.env.example` | The node's user, port and password placeholders; copy to `.env` (gitignored; `up` generates the password) |
| [`JOIN.md`](JOIN.md) | How to add a machine to the pool, safely (the volunteer's steps, then the admin's) |

## Secrets and the variable

| Setting | What |
|---|---|
| `MAROLA_BR_PROXY` (secret, required) | The pool: one `http://user:pass@host:port` per node, separated by whitespace or newlines, tried in order. Unset or empty: the flight check fails |
| `BR_PROXY_REQUIRED` (variable, unset) | The break glass: `false` turns every flight-check failure into a warning and the build runs without the proxy. Anything else, or unset, is required |

The nodes' public addresses and passwords live only in that secret. Adding and removing nodes,
and rotating a password, are the admin's steps in [JOIN.md](JOIN.md). The pool, its volunteers and
the secret are a person's job: AGENTS.md's cost rule keeps provisioning with a human, and no agent
dispatches a workflow.

- Uptime: one healthy node at each 3-hourly run is enough, and more nodes make that likelier. A
  run that finds none deploys nothing; the site stays as last deployed until a run finds one.

### Rejected

- **Public proxy lists:** entries die within hours, and nobody knows who runs them.
- **Oracle Cloud Always Free:** needs a card and a $1 hold, and reclaims idle VMs.
- **A Vercel function in `gru1`:** a URL relay, not a CONNECT proxy, and Hobby is non-commercial only.
- **ScraperAPI:** Brazilian exits only on the Business plan.
- **Webshare's free tier:** Brazil on it unverified, and a third party sees the traffic.
- **GCP, AWS, Azure VMs:** each needs a card.
- **A self-hosted runner in Brazil:** GitHub advises against them on public repos.
- **Azure private networking for hosted runners:** paid.

## INEMA's plain-HTTP first request

INEMA now redirects `http://` to `https://` with a valid certificate (checked 2026-10-06 from
Brazil), but marola-app's `InemaBaWaterQualityClient` still requests
`http://balneabilidade.inema.ba.gov.br/...`. Through the pool, that first request is plain HTTP, so
a node's operator could read or alter it before the redirect. The fix belongs in marola-app (request
`https://`). Until it lands, the node allows plain `http://` to INEMA; tunnels (`CONNECT`) go to
port 443 only. The same app code also does not follow that redirect: on this PR's CI run INEMA
failed with `HTTP 301 for http://balneabilidade.inema.ba.gov.br/...`, so Salvador reads "no data"
with or without the pool until marola-app requests `https://`.

## Checking it

```bash
scripts/br-proxy.sh --self-test            # the runner side: config, upstream parsing, fallbacks
scripts/br-proxy-preflight.sh --self-test  # the flight check, with curl stubbed
just br-proxy-node check                   # on a node: the agencies answer, everything else is refused
just br-proxy-node check --from-outside http://user:pass@host:port   # from another network
```

In a `site.yml` run, the "Flight check" step names the node it chose (host and port) and its latency, and "What
went through the Brazilian proxy" lists the routing decisions of the runner's tinyproxy.
