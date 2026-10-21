# Joining the marola proxy pool, safely

The map's build reaches Rio's (INEA) and Bahia's (INEMA) bathing-water agencies, which answer only
Brazilian addresses, through small proxies on volunteers' machines in Brazil
([README.md](README.md) has the design). This page is the whole setup, step by step.

## 0. What Headscale is here

The runner and the volunteers' machines form a small private network (it runs on the Tailscale
client) that lets the CI runner reach one port on a volunteer's machine in Brazil, and nothing
else. Nobody opens a port on a router, and the machines see only what the network's single rule
allows. Its coordination server is **Headscale**, open source and self-hosted by the org (it
replaced Tailscale's, whose trial ended).

- **Admin:** hosts the Headscale server once, and hands out keys.
- **Server side, a proxy node:** a volunteer's machine running `just br-proxy-node`, tagged
  `tag:br-proxy`.
- **Client side, CI:** the GitHub runner of `site.yml`, tagged `tag:ci`, which joins for one run
  with a pre-auth key and is removed afterwards (an ephemeral node).

**The build depends on it.** `site.yml`'s flight check fails closed: when the runner cannot join
(the Headscale server being down included), or no `tag:br-proxy` node passes a real request to
INEA, the job stops before any board is built. Nothing deploys, and marola.dev keeps serving the
last deployed site, for **every** area (Florianópolis's forecast too), until a node is healthy
again or the break glass below is used.

## 1. Admin, once: the Headscale server

1. **Host it.** It needs a machine that is always on and reachable from the internet over HTTPS (a
   public IPv4/IPv6, or a forwarded port 443; CGNAT, common on Brazilian home connections, breaks
   this), a DNS A/AAAA record for its name (dynamic DNS if the IP changes), and Docker. It can be
   the same machine as a pool node. Cost: $0. The server, its domain and the keys are a person's
   job (AGENTS.md's cost rule).

   ```bash
   cp ops/br-proxy/headscale/.env.example ops/br-proxy/headscale/.env
   # edit it: HEADSCALE_HOST is the public DNS name that points at this machine
   just headscale up           # Let's Encrypt is built in; ports 80 and 443 must reach it
   ```

   Check `https://<HEADSCALE_HOST>/health` from outside the machine. `just headscale logs` shows
   why if it does not answer. Back up the sqlite volume; losing it only means re-enrolling the
   nodes.
2. **The policy is in the repo** (`ops/br-proxy/headscale/`), nothing to edit in a console (Headscale
   has none). It is one grant: `tag:ci` to `tag:br-proxy` on `tcp:8888`. CI reaches port 8888 on
   pool nodes and nothing else; nothing is granted *from* `tag:br-proxy`, so a node reaches neither
   another node, nor CI, nor any other device.
3. **The CI key and URL.** `just headscale key-ci` prints a reusable, ephemeral pre-auth key tagged
   `tag:ci`. Store it, and the server's URL, as marola-site's secrets and variables
   (<https://github.com/marola-dev/marola-site/settings/secrets/actions>; needs repo admin):

   ```bash
   just headscale key-ci | gh secret set HEADSCALE_AUTHKEY -R marola-dev/marola-site
   gh variable set HEADSCALE_URL -R marola-dev/marola-site --body https://<HEADSCALE_HOST>
   ```

   The key **expires after 90 days**: rotate it by repeating this step (a recurring chore; the
   flight check reports a missing or refused key). Then delete the old `TAILSCALE_OAUTH_CLIENT_ID`
   and `TAILSCALE_OAUTH_SECRET` secrets.
4. **One key per volunteer**: `just headscale key-node` prints a one-off pre-auth key tagged
   `tag:br-proxy`: **not reusable**, **not ephemeral** (the node should survive restarts), 1 day
   expiry (it matters only for the first join). There is no device approval step; the tag and the
   one-off key are the control. Send it over a private channel (a direct message, not an issue, PR,
   or group chat), together with the server's URL.
5. **Leave `BR_PROXY_REQUIRED` unset.** Unset means true: no healthy node, no deploy. It is a
   repo *variable* (<https://github.com/marola-dev/marola-site/settings/variables/actions>), the
   break glass: set to `false`, the build goes on without the proxy (Rio and Salvador water
   quality read "no data") so the rest of the map keeps updating. Set it only while the pool is
   down, and delete it as soon as a node is back. Never make it the default.
6. **Revoking a node**: `just headscale nodes` lists them with their ids, then:

   ```bash
   docker compose -f ops/br-proxy/headscale/compose.yml exec headscale headscale nodes delete --identifier <id>
   ```

   Its one-off key is already spent.

## 2. Server side: a volunteer's proxy node

**You need** a machine in Brazil that is on often (a home server, a desktop left on, a
Raspberry Pi), Docker with the Compose plugin, `git`, `just` (or `nix develop` in the repo, which
has it), and a residential connection is fine. You do **not** install Tailscale on the machine: it
runs inside a container, so your own Tailscale, if you have one, is unaffected.

**What you share.** The two agencies see your home IP as the one asking for their bulletins, a
few times a day, a few megabytes at most. The proxy reaches only those two hosts. Everything is
HTTPS except INEMA's first request, which is plain HTTP until marola-app is fixed (README.md).

**What runs.** Two containers (`ops/br-proxy/compose.yml`): the official `tailscale/tailscale`
image (pinned by digest) and our own small proxy (`ops/br-proxy/proxy/`, built from source in the image) inside its network namespace, listening only on that
namespace's loopback. They publish no port on your machine or LAN. The recipe installs nothing on
the host, and stops if Docker or Compose is missing.

```bash
git clone https://github.com/marola-dev/marola-site && cd marola-site
cp ops/br-proxy/.env.example ops/br-proxy/.env
# edit ops/br-proxy/.env: set HEADSCALE_URL (the admin sends it), paste the key after TS_AUTHKEY=,
# and name the node (BR_PROXY_NODE_NAME, e.g. br-proxy-yourname). Or leave TS_AUTHKEY empty and `up` asks for it without showing it.
just br-proxy-node up       # joins the pool; the key is used once
just br-proxy-node check
just br-proxy-node status   # network, name, tag, uptime
```

`check` should print:

```
  ok   https://www.inea.rj.gov.br/ answers through the node (HTTP 200)
  ok   http://balneabilidade.inema.ba.gov.br/ answers through the node (HTTP 301)
  ok   http://example.com/ is refused (403)
  ok   https://example.com/ is refused (CONNECT 403)
  ok   a tunnel to a port other than 443 is refused (CONNECT 403)
  ok   egress looks Brazilian (São Paulo)
  ok   on the network
br-proxy-node check: ok
```

The "egress" line asks Tailscale's own netcheck for the nearest relay (no third-party IP
service) and warns if it is not São Paulo, since a machine whose traffic leaves Brazil (through a
VPN, say) is no use to the agencies.

**For the admin**, `just headscale nodes` lists the node under its name with the tag
`tag:br-proxy`.

**Keeping it running.** Both containers restart unless stopped, so the node comes back after a
reboot once Docker starts. Its identity lives in the `marola-br-proxy_state` volume; you can
delete `TS_AUTHKEY` from `.env` after the first `up`, it is spent anyway.

**A node that joined the old Tailscale tailnet** keeps that identity in its state volume and never
asks the Headscale server: `just br-proxy-node down`, `docker volume rm marola-br-proxy_state`, add
`HEADSCALE_URL` and a new one-off key to `.env`, then `just br-proxy-node up`.

**Stopping:** `just br-proxy-node down` (it keeps its identity for the next `up`). **Leaving the
pool:** `down`, ask the admin to remove the node, then `docker volume rm marola-br-proxy_state`.

**Do not:** reuse or share a key; change `hosts`, `proxy/` or the compose file (the allowlist
is what keeps your node from being anyone's open proxy); publish port 8888, or run the proxy
outside these containers.

## 3. Client side: CI (nothing to install)

Every `site.yml` run (schedule, push, dispatch, and same-repo PRs):

1. `tailscale/github-action` (pinned by commit SHA) joins as an ephemeral `tag:ci` node, with
   `HEADSCALE_AUTHKEY` and `--login-server=$HEADSCALE_URL`; the tag comes from the key
   ([GitHub Action](https://tailscale.com/kb/1276/tailscale-github-action)).
2. The flight check (`scripts/br-proxy-preflight.sh`) lists the online `tag:br-proxy` peers and
   tries each, ~10 s apiece and 60 s in all, with a real request to `https://www.inea.rj.gov.br/`;
   the first 2xx/3xx is used.
3. A tinyproxy on the runner sends only INEA's and INEMA's hosts through that node, everything
   else direct, and the board build runs. When the job ends, the ephemeral node disappears.

**Verifying it:** wait for the next scheduled `site.yml` run (or start one from Actions → site →
*Run workflow*, which also deploys) and look for
`br-proxy-preflight: using <node> (<ip>): https://www.inea.rj.gov.br/ answered HTTP 200 in 0.4s`
in the "Flight check" step, and for "What went through the Brazilian proxy" listing INEA's host.
In `just headscale nodes`, an ephemeral `tag:ci` node appears during the run and goes away after it.

**Reading a failure.** Every flight-check error starts `::error::br-proxy flight check:` and ends
with what happens next (no boards, no deploy, the last site stays up, the break glass). The cause:

| The error says | It means | Do |
|---|---|---|
| `HEADSCALE_AUTHKEY/HEADSCALE_URL are not set` | the secret or the variable is missing | step 1.3 |
| `the tailnet join failed (failure)` | the key expired or was refused, or the Headscale server was unreachable | check the join step, `https://<host>/health`, `just headscale logs`; rotate the key (1.3) |
| `no tag:br-proxy node is online` | no volunteer node is up | `just br-proxy-node up` on a node; `status` there |
| `tag:br-proxy nodes are online, but none passed the request to …` | a node is up but cannot reach INEA (or the grant is wrong) | `just br-proxy-node check` on the node; the policy in step 1.2 |
| `the runner's router did not come up through the chosen proxy` | the node passed the check but failed the second probe | re-run; then `check` on the node |

## 4. Turning the pool on, in order

1. Admin: steps 1.1 to 1.3 (the Headscale server, its policy, the CI key and URL in the repo).
2. Admin: step 1.4, one key for the first node (the maintainer's own machine is fine).
3. Volunteer: section 2 (`up`, then `check` all ok, then `status` shows `tag:br-proxy`).
4. Wait for the next scheduled `site.yml` run (or start one from Actions → site → *Run workflow*)
   and confirm
   section 3's log line naming the node.

## What each side trusts (threat model)

- **A leaked CI credential** (the `HEADSCALE_AUTHKEY`, or a runner mid-job) can reach only port 8888 on
  pool nodes, and through them only the two agencies' hosts.
- **A node** can reach nothing on the network: there is no grant from `tag:br-proxy`. A hostile
  node can only answer the build's requests to the two agencies badly, and the flight check skips
  a node that does not answer.
- **The agencies** see the volunteer's IP address.
- **Tampering:** on HTTPS a node cannot read or change the bulletins (the app checks the
  agencies' certificates end to end). INEMA's first request is plain HTTP until marola-app
  requests `https://`; until then a hostile node could alter it.
- **Not covered:** a volunteer could log which of the two agencies the build asks for and when;
  that is public information anyway.
