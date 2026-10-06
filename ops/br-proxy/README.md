# The Brazilian proxy pool for INEA and INEMA (#4)

INEA (Rio's bathing-water bulletins) and INEMA (Bahia's) do not answer connections from outside
Brazil, and GitHub's runners are not in Brazil, so without help `site.yml`'s build gives Rio's and
Salvador's beaches "no data". This directory is the help: a pool of small proxies on volunteers'
machines in Brazil, reached over the org's Tailscale network (the tailnet), that the build sends
those two agencies through, and nothing else.

The build depends on it, and fails closed. Its flight check runs before any board is built: when
the runner cannot join the tailnet, or no node passes a real request to INEA, the job stops with an
`::error::` naming the cause. Nothing deploys, and marola.dev keeps serving the last deployed site.
While no node is healthy, that holds for **every** area, Florianópolis's forecast too. The repo
variable `BR_PROXY_REQUIRED=false` is the break glass: the build then goes on without the proxy
(Rio and Salvador water quality "no data"). Unset means required; set it only while the pool is
down, and delete it afterwards.

```
site.yml build job (GitHub runner)
  ├─ tailscale/github-action: joins the tailnet as tag:ci (TAILSCALE_OAUTH_CLIENT_ID / TAILSCALE_OAUTH_SECRET)
  ├─ scripts/br-proxy-preflight.sh: the flight check, the first online tag:br-proxy node through
  │    which https://www.inea.rj.gov.br/ really answers (2xx/3xx), ~10 s per node, 60 s in all;
  │    none, or no tailnet: exit 1, the job stops (unless BR_PROXY_REQUIRED=false)
  ├─ scripts/br-proxy.sh start: a tinyproxy on the runner's 127.0.0.1:8899 that sends the hosts in
  │    ./hosts through that node and everything else (Overpass, Open-Meteo) direct
  └─ the app image, with --network host and JDK_JAVA_OPTIONS pointing its JVM at 127.0.0.1:8899
        └─> pool node in Brazil (./compose.yml: tailscale + tinyproxy, ./node.conf, ./filter)
              └─> www.inea.rj.gov.br / balneabilidade.inema.ba.gov.br
```

| File | What it is |
|---|---|
| `hosts` | The Brazil-only hosts the runner routes through the pool. Keep `filter` in step |
| `filter` | The node's allowlist: those two agencies' domains, nothing else |
| `node.conf` | The node's tinyproxy: loopback only, `FilterDefaultDeny`, tunnels to 443 only |
| `compose.yml`, `Dockerfile` | The node: the official `tailscale/tailscale` image and tinyproxy in its network namespace |
| `.env.example` | The node's one-off auth key placeholder; copy to `.env` (gitignored) |
| [`JOIN.md`](JOIN.md) | How to add a machine to the pool, safely (the admin's one-time setup and the volunteer's steps) |

## Secrets and the variable

| Setting | What |
|---|---|
| `TAILSCALE_OAUTH_CLIENT_ID`, `TAILSCALE_OAUTH_SECRET` (secrets, required) | A Tailscale OAuth client (`auth_keys` scope, tag `tag:ci`). `site.yml` joins the tailnet with it on every run. Missing: the flight check fails |
| `MAROLA_BR_PROXY` (secret, optional) | An override: any HTTP forward proxy in Brazil reachable from the runner, as `http://[user:pass@]host:port`, used instead of the pool. It is still probed; a dead one fails the flight check |
| `BR_PROXY_REQUIRED` (variable, unset) | The break glass: `false` turns every flight-check failure into a warning and the build runs without the proxy. Anything else, or unset, is required |

## The Brazilian end: Tailscale (free)

The tailnet is how a runner reaches a volunteer's machine without anyone opening a port on their
router. Tailscale's **Personal plan costs $0**: up to 6 users, 50 tagged resources, and 1,000
ephemeral-node minutes a month, which is what the CI runners use, since each one joins as an
ephemeral node and is removed after the job ([pricing](https://tailscale.com/pricing),
[ephemeral nodes](https://tailscale.com/docs/features/ephemeral-nodes)).

- The tailnet belongs to the **org's identity**, not a volunteer's personal account.
- Whether a nonprofit may use the Personal plan is **unverified**; Tailscale gives nonprofit
  pricing on request.
- Access is one rule: replace the default allow-all policy with a single grant,
  `{"src": ["tag:ci"], "dst": ["tag:br-proxy"], "ip": ["tcp:8888"]}`
  ([grants](https://tailscale.com/kb/1324/grants)). CI reaches only port 8888 on the nodes; the
  nodes reach nothing.
- Uptime: one healthy node at each 3-hourly run is enough, and more nodes make that likelier. A
  run that finds none deploys nothing; the site stays as last deployed until a run finds one.

The admin's one-time setup and a volunteer's steps are in [JOIN.md](JOIN.md). Creating the
tailnet, the OAuth client and the keys is a person's job: AGENTS.md's cost rule keeps provisioning
with a human, and no agent dispatches a workflow.

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
scripts/br-proxy-preflight.sh --self-test  # the flight check, with tailscale and curl stubbed
just br-proxy-node check                   # on a node: the agencies answer, everything else is refused
```

In a `site.yml` run, the "Flight check" step names the node it chose and its latency, and "What
went through MAROLA_BR_PROXY" lists the routing decisions of the runner's tinyproxy.
