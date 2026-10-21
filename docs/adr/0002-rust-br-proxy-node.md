# ADR-0002: The pool node is our own Rust proxy, public and password-protected

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-10-21 |
| **Issue** | [#171](https://github.com/marola-dev/marola-site/issues/171) |

## Context

The Brazilian proxy pool's nodes ran tinyproxy, a general proxy configured down to two agencies
with a regex filter, behind a Tailscale tailnet. The tailnet is gone: the SaaS trial ended (every
run failed with 402), and a self-hosted coordination server would be one more always-on public
service, while nodes need a forwarded port anyway.

## Decision

Each volunteer's node is `ops/br-proxy/proxy/`, a Rust proxy using only std, published on a port
the volunteer forwards on their router. CI reaches the nodes directly, from the secret
`MAROLA_BR_PROXY`.

- **Basic auth is mandatory** off loopback: without a correct `Proxy-Authorization` the answer is
  `407`, checked before the allowlist so an unauthenticated client learns nothing. The compare is
  constant-time. The proxy refuses to start on a non-loopback address without auth, or with a
  password under 16 characters.
- **An exact allowlist** (the `hosts` file, which the runner's router also reads): `CONNECT` to
  port 443 only, plain HTTP to port 80 only, a client limit and timeouts. No subdomain is allowed
  unless it is listed.
- The container runs read-only, without capabilities, as `nobody`. It costs $0.

Rust lives only in `ops/br-proxy/proxy/` in this repo (ADR-0001 covers `agents/`). The runner-side
router (`scripts/br-proxy.sh`, tinyproxy on the GitHub runner) is not part of this decision. The
Docker build is what nodes run: it builds and tests the crate in a pinned `rust:*-alpine` image,
and the runtime image carries only the binary. `just quality` runs `cargo fmt --check`, clippy with
`-D warnings` and `cargo test`.

## Consequences

- Volunteers need a public address and a forwarded port; CGNAT breaks it.
- The password crosses the internet in Basic auth over plain HTTP to the node (the agencies' HTTPS
  stays encrypted end to end inside the tunnel). A sniffed password lets someone fetch the two
  public agency sites through the node, and nothing else; rotating it is the remedy.
- We own the security of an internet-facing proxy. The tests are the contract: `407` before `403`,
  and every refusal (other hosts, other ports, IP literals, `https://` in absolute form,
  origin-form requests) end to end against the running server, as are the tunnel and the plain-HTTP
  forward.
- Bumping the Rust image is a `Dockerfile` edit (tag and digest), and its tests must pass in the build.
