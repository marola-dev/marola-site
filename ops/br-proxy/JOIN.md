# Joining the marola proxy pool, safely

The map's build reaches Rio's (INEA) and Bahia's (INEMA) bathing-water agencies, which answer only
Brazilian addresses, through small proxies on volunteers' machines in Brazil
([README.md](README.md) has the design). This page is the whole setup, step by step.

## 0. What Tailscale is here

Tailscale is a private network (a "tailnet") that lets the CI runner reach one port on a
volunteer's machine in Brazil, and nothing else. Nobody opens a port on a router, and the
machines see only what the tailnet's single rule allows.

- **Admin:** sets up the org's tailnet once, and hands out keys.
- **Server side, a proxy node:** a volunteer's machine running `just br-proxy-node`, tagged
  `tag:br-proxy`.
- **Client side, CI:** the GitHub runner of `site.yml`, tagged `tag:ci`, which joins for one run
  through an OAuth client and is removed afterwards (an ephemeral node).

**The build depends on it.** `site.yml`'s flight check fails closed: when the runner cannot join
the tailnet, or no `tag:br-proxy` node passes a real request to INEA, the job stops before any
board is built. Nothing deploys, and marola.dev keeps serving the last deployed site, for **every**
area (Florianópolis's forecast too), until a node is healthy again or the break glass below is
used.

Admin console links below go through Tailscale's login, so their paths could not be checked
without an account; the page names are the ones Tailscale's docs use (checked 2026-10-06).

## 1. Admin, once: the org's tailnet

1. **Sign up with the org's identity**: <https://login.tailscale.com/start> → *Sign up with
   GitHub* → *Authorize tailscale* → on *Select a tailnet*, pick the **marola-dev organization**,
   not a personal account. Tailscale supports a GitHub organization as the tailnet's identity, and
   whoever does this must be an **owner of the GitHub organization**
   ([GitHub identity](https://tailscale.com/docs/integrations/identity/github)). The tailnet then
   belongs to marola-dev, not to a person. The plan is the free Personal plan
   ([pricing](https://tailscale.com/pricing)); whether a nonprofit may use it is unverified
   (Tailscale gives nonprofit pricing on request). Admin console: <https://login.tailscale.com/admin>.
2. **Access controls** (<https://login.tailscale.com/admin/acls>, the JSON editor). Replace the
   whole default policy, its allow-all rule and its `ssh` section included, with:

   ```json
   {
     "tagOwners": {
       "tag:ci": ["autogroup:admin"],
       "tag:br-proxy": ["autogroup:admin"]
     },
     "grants": [
       {"src": ["tag:ci"], "dst": ["tag:br-proxy"], "ip": ["tcp:8888"]}
     ]
   }
   ```

   That is the only grant ([grants](https://tailscale.com/kb/1324/grants),
   [tags](https://tailscale.com/kb/1068/tags)). CI reaches port 8888 on pool nodes and nothing
   else; nothing is granted *from* `tag:br-proxy`, so a node reaches neither another node, nor
   CI, nor any other device. The admin's own devices lose access too, which is intended.
3. **Device approval on**: the *Device management* page,
   <https://login.tailscale.com/admin/settings/device-management>
   ([device approval](https://tailscale.com/kb/1099/device-approval)).
4. **The CI OAuth client**: the *Trust credentials* page,
   <https://login.tailscale.com/admin/settings/trust-credentials> → *Credential* → *OAuth*;
   scope `auth_keys` (write), tag `tag:ci`
   ([OAuth clients](https://tailscale.com/kb/1215/oauth-clients)). Copy its ID and secret into
   marola-site's repo secrets **`TS_OAUTH_CLIENT_ID`** and **`TS_OAUTH_SECRET`**:
   <https://github.com/marola-dev/marola-site/settings/secrets/actions> (Settings → Secrets and
   variables → Actions; needs repo admin).
5. **One auth key per volunteer**: the *Keys* page, <https://login.tailscale.com/admin/settings/keys>
   → *Generate auth key*: **not reusable** (one-off), **pre-approved**, **tagged** `tag:br-proxy`,
   **not ephemeral** (the node should survive restarts), short expiry (1 day is plenty: the key
   matters only for the first join) ([auth keys](https://tailscale.com/kb/1085/auth-keys)). Send
   it over a private channel (a direct message, not an issue, PR, or group chat).
6. **Leave `BR_PROXY_REQUIRED` unset.** Unset means true: no healthy node, no deploy. It is a
   repo *variable* (<https://github.com/marola-dev/marola-site/settings/variables/actions>), the
   break glass: set to `false`, the build goes on without the proxy (Rio and Salvador water
   quality read "no data") so the rest of the map keeps updating. Set it only while the pool is
   down, and delete it as soon as a node is back. Never make it the default.
7. **Revoking a node**: the *Machines* page, <https://login.tailscale.com/admin/machines> → the
   node → *Remove*. Its one-off key is already spent.

## 2. Server side: a volunteer's proxy node

**You need** a machine in Brazil that is on often (a home server, a desktop left on, a
Raspberry Pi), Docker with the Compose plugin, `git`, `just` (or `nix develop` in the repo, which
has it), and a residential connection is fine. You do **not** install Tailscale on the machine: it
runs inside a container, so your own Tailscale, if you have one, is unaffected.

**What you share.** The two agencies see your home IP as the one asking for their bulletins, a
few times a day, a few megabytes at most. The proxy reaches only those two hosts. Everything is
HTTPS except INEMA's first request, which is plain HTTP until marola-app is fixed (README.md).

**What runs.** Two containers (`ops/br-proxy/compose.yml`): the official `tailscale/tailscale`
image (pinned by digest) and a tinyproxy inside its network namespace, listening only on that
namespace's loopback. They publish no port on your machine or LAN. The recipe installs nothing on
the host, and stops if Docker or Compose is missing.

```bash
git clone https://github.com/marola-dev/marola-site && cd marola-site
cp ops/br-proxy/.env.example ops/br-proxy/.env
# edit ops/br-proxy/.env: paste the key after TS_AUTHKEY=, and name the node (BR_PROXY_NODE_NAME,
# e.g. br-proxy-yourname). Or leave TS_AUTHKEY empty and `up` asks for it without showing it.
just br-proxy-node up       # joins the pool; the key is used once
just br-proxy-node check
just br-proxy-node status   # tailnet, name, tag, uptime
```

`check` should print:

```
  ok   https://www.inea.rj.gov.br/ answers through the node (HTTP 200)
  ok   http://balneabilidade.inema.ba.gov.br/ answers through the node (HTTP 301)
  ok   http://example.com/ is refused (403)
  ok   https://example.com/ is refused (CONNECT 403)
  ok   a tunnel to a port other than 443 is refused (CONNECT 403)
  ok   egress looks Brazilian (São Paulo)
  ok   on the tailnet
br-proxy-node check: ok
```

The "egress" line asks Tailscale's own netcheck for the nearest relay (no third-party IP
service) and warns if it is not São Paulo, since a machine whose traffic leaves Brazil (through a
VPN, say) is no use to the agencies.

**In the admin console** (Machines), the node shows up under its name with the tag
`tag:br-proxy` and key expiry disabled (tagged devices do not expire).

**Keeping it running.** Both containers restart unless stopped, so the node comes back after a
reboot once Docker starts. Its identity lives in the `marola-br-proxy_state` volume; you can
delete `TS_AUTHKEY` from `.env` after the first `up`, it is spent anyway.

**Stopping:** `just br-proxy-node down` (it keeps its identity for the next `up`). **Leaving the
pool:** `down`, ask the admin to remove the device, then `docker volume rm marola-br-proxy_state`.

**Do not:** reuse or share a key; change `filter`, `node.conf` or the compose file (the allowlist
is what keeps your node from being anyone's open proxy); publish port 8888, or run tinyproxy
outside these containers.

## 3. Client side: CI (nothing to install)

Every `site.yml` run (schedule, push, dispatch, and same-repo PRs):

1. `tailscale/github-action` (pinned by commit SHA) joins as an ephemeral `tag:ci` node with
   `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET`
   ([GitHub Action](https://tailscale.com/kb/1276/tailscale-github-action),
   [ephemeral nodes](https://tailscale.com/docs/features/ephemeral-nodes)).
2. The flight check (`scripts/br-proxy-preflight.sh`) lists the online `tag:br-proxy` peers and
   tries each, ~10 s apiece and 60 s in all, with a real request to `https://www.inea.rj.gov.br/`;
   the first 2xx/3xx is used.
3. A tinyproxy on the runner sends only INEA's and INEMA's hosts through that node, everything
   else direct, and the board build runs. When the job ends, the ephemeral node disappears.

**Verifying it:** re-run the PR's `build` check (or wait for the next scheduled run) and look for
`br-proxy-preflight: using <node> (<ip>): https://www.inea.rj.gov.br/ answered HTTP 200 in 0.4s`
in the "Flight check" step, and for "What went through the Brazilian proxy" listing INEA's host.
On Machines, an ephemeral `tag:ci` node appears during the run and goes away after it.

**Reading a failure.** Every flight-check error starts `::error::br-proxy flight check:` and ends
with what happens next (no boards, no deploy, the last site stays up, the break glass). The cause:

| The error says | It means | Do |
|---|---|---|
| `TS_OAUTH_CLIENT_ID/TS_OAUTH_SECRET are not set` | the secrets are missing | step 1.4 |
| `the tailnet join failed (failure)` | the OAuth client was refused, or Tailscale was unreachable | check the "Join the tailnet" step, the client's scope and tag |
| `no tag:br-proxy node is online in the tailnet` | no volunteer node is up | `just br-proxy-node up` on a node; `status` there |
| `tag:br-proxy nodes are online, but none passed the request to …` | a node is up but cannot reach INEA (or the grant is wrong) | `just br-proxy-node check` on the node; the policy in step 1.2 |
| `this is a fork's PR …` | fork PRs get no secrets | a maintainer runs the check from a branch of this repo |
| `the runner's router did not come up through the chosen proxy` | the node passed the check but failed the second probe | re-run; then `check` on the node |

## 4. Turning the pool on, in order

1. Admin: steps 1.1 to 1.4 (tailnet, policy, device approval, the CI OAuth client and its two
   repo secrets).
2. Admin: step 1.5, one key for the first node (the maintainer's own machine is fine).
3. Volunteer: section 2 (`up`, then `check` all ok, then `status` shows `tag:br-proxy`).
4. Re-run a `site.yml` build (a PR's `build` check, or the next scheduled run) and confirm
   section 3's log line naming the node.

## What each side trusts (threat model)

- **A leaked CI credential** (the OAuth client, or a runner mid-job) can reach only port 8888 on
  pool nodes, and through them only the two agencies' hosts.
- **A node** can reach nothing in the tailnet: there is no grant from `tag:br-proxy`. A hostile
  node can only answer the build's requests to the two agencies badly, and the flight check skips
  a node that does not answer.
- **The agencies** see the volunteer's IP address.
- **Tampering:** on HTTPS a node cannot read or change the bulletins (the app checks the
  agencies' certificates end to end). INEMA's first request is plain HTTP until marola-app
  requests `https://`; until then a hostile node could alter it.
- **Not covered:** a volunteer could log which of the two agencies the build asks for and when;
  that is public information anyway.
