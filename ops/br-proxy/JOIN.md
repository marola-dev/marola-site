# Joining the marola proxy pool

The map's build reaches Rio's (INEA) and Bahia's (INEMA) bathing-water agencies, which answer only
Brazilian addresses, through small proxies on volunteers' machines in Brazil
([README.md](README.md) has the design). Your machine runs one container, protected by a password,
on a port you forward on your router. This page is the whole setup, step by step.

**The build depends on it.** `site.yml`'s flight check fails closed: when no node passes a real
request to INEA, the job stops before any board is built. Nothing deploys, and marola.dev keeps
serving the last deployed site, for **every** area, until a node is healthy again or the break
glass below is used.

## 1. Volunteer: run a node

**You need**

- a machine in Brazil that stays on (a home server, a desktop left on, a Raspberry Pi);
- Docker with the Compose v2 plugin, `git`, and `just` (or `nix develop` in the repo, which has it);
- a public IPv4 or IPv6 address reachable from the internet. CGNAT, common on Brazilian home
  connections, breaks this: compare your router's WAN IP (in its admin page) with
  `curl -4 ifconfig.me`; if they differ, you are behind CGNAT, and your ISP may give you a public
  address on request;
- ideally a static IP, or a dynamic DNS name (No-IP, DuckDNS) that follows yours.

**Steps**

```bash
git clone https://github.com/marola-dev/marola-site && cd marola-site
cp ops/br-proxy/.env.example ops/br-proxy/.env     # optional: edit BR_PROXY_USER and BR_PROXY_PORT
just br-proxy-node up
```

1. `up` builds the proxy, starts it, makes a 24-character password in `ops/br-proxy/.env` if there
   is none, and prints one line: `http://<user>:<password>@<YOUR_PUBLIC_IP_OR_DNS>:<port>`. It
   cannot know your public address; you fill that in.
2. **Forward TCP `<port>` (8888 by default) on your router** to this machine's LAN address. Give the
   machine a fixed LAN address (a DHCP reservation) so the forward does not break.
3. `just br-proxy-node check` on the machine. It should print:

   ```
     ok   https://www.inea.rj.gov.br/ answers through the node (HTTP 200)
     ok   http://balneabilidade.inema.ba.gov.br/ answers through the node (HTTP 301)
     ok   http://example.com/ is refused (403)
     ok   https://example.com/ is refused (CONNECT 403)
     ok   a tunnel to a port other than 443 is refused (CONNECT 403)
     ok   no password: refused (407)
     ok   a wrong password: refused (407)
   br-proxy-node check: ok
   ```

   The INEA line also proves your traffic leaves from Brazil: the agencies refuse other addresses.
4. From **another network** (your phone's hotspot, with the laptop on it), prove the port forward:

   ```bash
   just br-proxy-node check --from-outside http://<user>:<password>@<your public address>:<port>
   ```

5. Send the line, with your public address filled in, to the admin over a **private channel** (a
   direct message; never an issue, a PR or a group chat). Never post it anywhere else.

`status` shows the container's state and uptime.

**Keeping it running.** The container restarts unless stopped, so the node comes back after a
reboot once Docker starts. If your IP changes and you have no DNS name, tell the admin the new one.

**Stopping:** `just br-proxy-node down` (`up` brings it back with the same password).
**Leaving the pool:** tell the admin first (so CI stops using the node), then `just br-proxy-node
down`, remove the forward on your router, `docker image rm marola-br-proxy-proxy`, and delete
`ops/br-proxy/.env`.

**What the node exposes, and why the risk is small.** It is an open port on the internet, so be
clear about it. The proxy answers 407 to anyone without the password, before anything else.
With the password it forwards only `CONNECT` on port 443 and plain HTTP on port 80, and only to
the two agencies' exact host names (`ops/br-proxy/hosts`); every other host, port or IP address
gets 403. So it cannot be used to reach your LAN or your machine, nor as a general proxy. The
agencies see your home IP, a few times a day, a few megabytes at most. The container is read-only,
runs as `nobody` and drops every capability.

**Never:** post the line, the `.env` or the password anywhere public; change `hosts`, `proxy/` or
the compose file (the allowlist is what keeps your node from being anyone's proxy); set a password
under 16 characters (the proxy refuses to start); publish any other port; run the proxy outside
the container.

## 2. Admin: the pool

The pool is the secret `MAROLA_BR_PROXY` (<https://github.com/marola-dev/marola-site/settings/secrets/actions>,
repo admin only): one `http://user:pass@host:port` per node, separated by whitespace or newlines,
tried in order. The nodes' addresses and passwords live nowhere else; keep them out of the repo, issues and chat.

- **Add or remove a node.** Edit a pool file *outside the repo*, then set the secret and delete the file:

  ```bash
  $EDITOR ~/pool.txt          # one entry per line
  gh secret set MAROLA_BR_PROXY -R marola-dev/marola-site < ~/pool.txt
  shred -u ~/pool.txt
  ```

  The secret cannot be read back, so keep the file (outside the repo, private) if you want to edit
  it later instead of re-collecting the lines.
- **Rotate a password** (leak, or a volunteer leaving): the volunteer sets a new
  `BR_PROXY_PASSWORD` in `ops/br-proxy/.env` (or empties it for a new one), runs `just br-proxy-node
  up`, and sends the new line; you replace the entry as above.
- **Break glass.** `BR_PROXY_REQUIRED` is a repo *variable*
  (<https://github.com/marola-dev/marola-site/settings/variables/actions>). Leave it unset (= true):
  no healthy node, no deploy. Set to `false`, the build goes on without the proxy (Rio and Salvador
  water quality read "no data") so the rest of the map keeps updating. Set it only while the pool is
  down, and delete it as soon as a node is back. Never make it the default.
- **Verify.** Wait for the next scheduled `site.yml` run (or start one from Actions → site → *Run
  workflow*, which also deploys) and look for
  `br-proxy-preflight: using <host>:<port>: https://www.inea.rj.gov.br/ answered HTTP 200 in 0.4s`
  in the "Flight check" step. The log never shows a password; GitHub masks them.

**Reading a failure.** Every flight-check error starts `::error::br-proxy flight check:` and ends
with what happens next (no boards, no deploy, the last site stays up, the break glass).

| The error says | It means | Do |
|---|---|---|
| `MAROLA_BR_PROXY is not set` | the secret is missing or empty | set it (above) |
| `none of the N pool node(s) …: host:port (HTTP 000)` | no answer: node off, IP changed, or the port forward is gone | ask the volunteer: `status`, then `check --from-outside` from another network |
| `… (HTTP 407)` | the password differs from the secret's | rotate (above) |
| `… (HTTP 403)` or `(HTTP 502)` | the node refuses the host, or cannot reach INEA (is its egress still Brazilian?) | `just br-proxy-node check` on the node |
| `skipping entry #N: not http://user:pass@host:port` (a log line) | a malformed entry in the secret | fix the entry |
| `the runner's router did not come up through the chosen proxy` | the node passed the check but failed the second probe | re-run; then `check` on the node |

## 3. Turning the pool on, in order

1. A volunteer finishes section 1 (the maintainer's own machine is a fine first node).
2. The admin puts the line in the secret (section 2).
3. Wait for the next scheduled `site.yml` run and confirm the log line naming the node.

## What each side trusts (threat model)

- **The password crosses the internet in Basic auth over plain HTTP** to the node. The agencies'
  HTTPS stays end to end encrypted inside the CONNECT tunnel. Someone who sniffs the password can
  fetch the two public agency sites through that node, and nothing else. Rotate it if it leaks.
- **A node's public address** lives only in the GitHub secret (and with its volunteer).
- **A hostile node** can only answer the build's requests to the two agencies badly, and the
  flight check skips a node that does not answer. On HTTPS it cannot read or change the bulletins
  (the app checks the agencies' certificates end to end). INEMA's first request is plain HTTP until
  marola-app requests `https://`; until then a hostile node could alter it.
- **The agencies** see the volunteer's IP address.
- **Not covered:** a volunteer could log which of the two agencies the build asks for and when;
  that is public information anyway.
