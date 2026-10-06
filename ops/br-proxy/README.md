# The Brazilian proxy pool for INEA and INEMA (#4)

INEA (Rio's bathing-water bulletins) and INEMA (Bahia's) do not answer connections from outside
Brazil, and GitHub's runners are not in Brazil, so without help `site.yml`'s build gives Rio's and
Salvador's beaches "no data". This directory is the help: a pool of small proxies on volunteers'
machines in Brazil, reached over the org's Tailscale network (the tailnet), that the build sends
those two agencies through, and nothing else.

All of it is optional. With no pool, no healthy node, or no secrets, the build runs exactly as it
did before (#4's "no data" for those agencies) and stays green.

```
site.yml build job (GitHub runner)
  ├─ tailscale/github-action: joins the tailnet as tag:ci (TS_OAUTH_CLIENT_ID / TS_OAUTH_SECRET)
  ├─ scripts/br-proxy-preflight.sh: the flight check, the first online tag:br-proxy node through
  │    which https://www.inea.rj.gov.br/ really answers (2xx/3xx), ~10 s per node, 60 s in all
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

## Secrets (all optional)

| Repo secret | What |
|---|---|
| `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` | A Tailscale OAuth client (`auth_keys` scope, tag `tag:ci`). With both set, `site.yml` joins the tailnet and runs the flight check; never on a PR |
| `MAROLA_BR_PROXY` | An override: any HTTP forward proxy in Brazil reachable from the runner, as `http://[user:pass@]host:port`. When set, it is used instead of the pool (still checked first; a dead one means no route) |

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
- Uptime: no node has to be up all the time. A run that finds no healthy node is "no data" for
  those two agencies until the next run three hours later, and the build stays green.

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
port 443 only.

## Checking it

```bash
scripts/br-proxy.sh --self-test            # the runner side: config, upstream parsing, fallbacks
scripts/br-proxy-preflight.sh --self-test  # the flight check, with tailscale and curl stubbed
just br-proxy-node check                   # on a node: the agencies answer, everything else is refused
```

In a `site.yml` run, the "Flight check" step names the node it chose and its latency, and "What
went through MAROLA_BR_PROXY" lists the routing decisions of the runner's tinyproxy.
