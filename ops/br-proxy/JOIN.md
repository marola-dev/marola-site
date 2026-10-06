# Joining the marola proxy pool, safely

The map's build reaches Rio's (INEA) and Bahia's (INEMA) bathing-water agencies, which answer only
Brazilian addresses, through small proxies on volunteers' machines in Brazil
([README.md](README.md) has the design). This page is how a machine joins that pool: the org
admin's one-time setup first, then the volunteer's steps, then what each side is trusting.

## For the org admin, once

1. **Create the tailnet under the org's identity** (the marola-dev GitHub org or its shared
   account), on Tailscale's free Personal plan, not under a volunteer's personal account.
2. **Set the access policy** (Access controls → JSON editor). Replace the whole default policy,
   including its allow-all rule and its `ssh` section, with:

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

   That is the only grant ([grants](https://tailscale.com/kb/1324/grants)). CI reaches port 8888 on
   pool nodes and nothing else; nothing at all is granted *from* `tag:br-proxy`, so a node can
   reach neither another node, nor CI, nor any other device in the tailnet. The admin's own devices
   lose access too, which is intended.
3. **Turn on device approval** (Settings → Device management), so a device that joins with
   anything but a pre-approved key waits for you.
4. **Create the CI OAuth client** (Settings → OAuth clients): scope `auth_keys` (write), tag
   `tag:ci`. Store its ID and secret as the repo secrets **`TS_OAUTH_CLIENT_ID`** and
   **`TS_OAUTH_SECRET`** of marola-site (Settings → Secrets and variables → Actions). Runners join
   as ephemeral nodes and are removed when the job ends
   ([ephemeral nodes](https://tailscale.com/docs/features/ephemeral-nodes)).
5. **For each volunteer, generate one auth key** (Settings → Keys → Generate auth key):
   - **not reusable** (one-off), **pre-approved**, **tagged** `tag:br-proxy`, **not ephemeral**
     (the node should survive restarts), and with a **short expiry** (1 day is plenty: the key
     only matters for the first join).
   - Send it over a private channel (a direct message, not an issue, PR, or group chat).
6. **To remove a node**, delete the device (Machines → the node → Remove). That revokes it at
   once; the volunteer's key was already used up.

Nothing else is needed: the build finds healthy nodes by itself (the flight check in `site.yml`).

## For the volunteer

**You need** a machine in Brazil that is on often (a home server, a desktop left on, a
Raspberry Pi), with Docker and the Docker Compose plugin, plus `git` and `just`. A residential
connection is fine. The node does not have to be up all the time: when no node is up, the map
just shows "no data" for Rio and Salvador until the next build.

**What you share.** The two agencies see your home IP address as the one asking for their
bulletins, a few times a day, a few megabytes at most. The proxy only reaches those two hosts.
Everything is HTTPS (so you cannot see its content, nor can anyone else on the way), except INEMA's
first request, which is plain HTTP until marola-app is fixed (see README.md).

**What runs.** Two containers (`ops/br-proxy/compose.yml`): the official `tailscale/tailscale`
image and a tinyproxy that lives inside its network namespace. They do not use your machine's
network directly, publish no port on it or your LAN, and leave your own Tailscale, if you have one,
untouched. The recipe installs nothing on your machine.

```bash
git clone https://github.com/marola-dev/marola-site && cd marola-site
cp ops/br-proxy/.env.example ops/br-proxy/.env
# edit ops/br-proxy/.env: paste the key after TS_AUTHKEY=, and give the node a name you recognise
# (or leave TS_AUTHKEY empty, and the next command asks for it without showing it)
just br-proxy-node up       # joins the pool; the key is used once
just br-proxy-node check    # the agencies answer through your node, everything else is refused
just br-proxy-node status   # tailnet, name, tag, uptime
```

Once `up` has worked, the node keeps its identity in a Docker volume and comes back on its own
after a reboot. You can delete `TS_AUTHKEY` from `.env`; it is spent anyway.

`check` also asks Tailscale for its nearest relay and warns when it is not São Paulo, since a
machine whose traffic leaves Brazil (a VPN, for instance) is no use to the agencies.

**To leave:** `just br-proxy-node down`, ask the admin to remove the device, then
`docker volume rm marola-br-proxy_state` to forget the node's identity.

**Do not:**
- reuse a key, or share it: each key is for one machine, once;
- change `filter`, `node.conf` or the compose file: the allowlist is what keeps your node from
  being anyone's open proxy;
- publish port 8888 on your machine or LAN, or run tinyproxy outside these containers.

## What each side trusts (threat model)

- **A leaked CI credential** (the OAuth client, or a runner mid-job) can reach only port 8888 on
  pool nodes, and through them only the two agencies' hosts. It cannot reach anything else on a
  volunteer's machine or network.
- **A node** can reach nothing in the tailnet: there is no grant from `tag:br-proxy`. A hostile
  node can only answer the build's requests to the two agencies badly, and the flight check skips
  a node that does not answer.
- **The agencies** see the volunteer's IP address.
- **Tampering:** on HTTPS a node cannot read or change the bulletins (the app checks the
  agencies' certificates end to end). INEMA's first request is plain HTTP until marola-app requests
  `https://`; until then a hostile node could alter it.
- **Not covered:** a volunteer could log which of the two agencies the build asks for and when;
  that is public information anyway.
