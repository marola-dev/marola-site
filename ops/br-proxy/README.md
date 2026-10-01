# The Brazilian proxy for INEA and INEMA (#4)

INEA (Rio's bathing-water bulletins) and INEMA (Bahia's) do not answer connections from outside
Brazil, and GitHub's runners are not in Brazil. The map's build never calls an agency: it reads
what `water.yml` stored on `site-data` (`water/<agency>.json`). `water.yml` fetches each agency on
its own cadence (`site/water.json`) and sends the Brazil-only ones, and nothing else, through a
tinyproxy on a machine with a Brazilian address:

```
water.yml's fetch (the image's JVM) ──> tinyproxy on the runner (scripts/br-proxy.sh)
    ──> this proxy, in Brazil ──> INEA / INEMA
    (Overpass and Open-Meteo, for the throwaway board, go direct)
```

This proxy refuses every host but the two agencies (`filter`) and everyone without the password
(`BasicAuth`), so it lends nothing to anyone who finds it.

## Where it runs, for free

Any always-on Linux machine with a Brazilian public address and one open TCP port. The free one is
an **Oracle Cloud Always Free** VM: choose *Brazil East (São Paulo)* or *Brazil Southeast
(Vinhedo)* as the home region when signing up (Always Free resources only exist in the home
region), and create a `VM.Standard.E2.1.Micro` with Ubuntu 24.04. Creating the account and the VM is
a person's job: AGENTS.md's cost rule says no agent provisions a cloud resource.

A public "free proxy" list is not a substitute. Its entries live for hours, so the fetch would break
again within days. You cannot know who runs them. And INEMA is plain `http://`, so whoever runs the
proxy could rewrite Bahia's verdicts, which would put "PRÓPRIA" on a polluted beach.

## Setting it up

On the VM:

```bash
sudo apt-get update && sudo apt-get install -y tinyproxy
sudo cp tinyproxy.conf filter /etc/tinyproxy/      # this directory's two files
sudo sed -i "s/CHANGE-ME/$(openssl rand -hex 16)/" /etc/tinyproxy/tinyproxy.conf
sudo grep BasicAuth /etc/tinyproxy/tinyproxy.conf  # the password, for the secret below
# Oracle's Ubuntu images refuse everything but SSH in iptables, on top of the cloud firewall.
sudo iptables -I INPUT 6 -p tcp --dport 8888 -j ACCEPT && sudo netfilter-persistent save
sudo systemctl restart tinyproxy
```

In the cloud console, add an ingress rule for TCP 8888 to the VM subnet's security list.

From a machine **outside** Brazil, both of these must hold:

```bash
curl -sI -x http://marola:PASSWORD@VM_IP:8888 https://www.inea.rj.gov.br/rio-de-janeiro/  # HTTP 200
curl -sI -x http://marola:PASSWORD@VM_IP:8888 https://example.com/                        # 403, filtered
```

## Wiring it in

Add the repository secret **`MAROLA_BR_PROXY`** = `marola:PASSWORD@VM_IP:8888` (Settings → Secrets
and variables → Actions). That is all `water.yml` needs.

To check it, run `water.yml` by hand (Actions → water → Run workflow), or re-run a PR's `water`
checks. Each agency's "Check it is a real fetch" step fails unless that agency answered with
sampling points, and the "Route … through MAROLA_BR_PROXY" step says whether the agency's host
answered through the proxy.

With the proxy down, a fetch fails visibly and `site-data` keeps the last good one. The map keeps
showing that bulletin until the app's 45-day rule ages its samples out.
