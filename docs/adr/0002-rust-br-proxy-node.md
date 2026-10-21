# ADR-0002: The pool node's proxy is our own Rust binary

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-10-21 |
| **Issue** | [#171](https://github.com/marola-dev/marola-site/issues/171) |

## Why

The Brazilian proxy pool's nodes ran tinyproxy: a general proxy configured down to two agencies
with a regex filter and `ConnectPort 443`. Every feature it has that we switch off is surface we
carry on volunteers' machines. `ops/br-proxy/proxy/` is the proxy we need and nothing more: an
exact-name allowlist (the `hosts` file, which the runner's router already reads), `CONNECT` to
port 443 only, plain HTTP to port 80 only, a client limit and an idle timeout. It is std only, with no
dependencies, so there is nothing to audit but our own few hundred lines. It costs $0.

## Limits

Rust lives only in `ops/br-proxy/proxy/` in this repo (ADR-0001, in PR #175, covers `agents/`). The
runner-side router (`scripts/br-proxy.sh`, tinyproxy on the GitHub runner) is unchanged and is not
part of this decision.

## Toolchain

The Docker build is what nodes run: the `Dockerfile` builds and tests the crate in a `rust:*-alpine`
image pinned by tag and digest, and the runtime image carries only the static binary. For
development, the dev shell provides `cargo`, `rustc`, `clippy` and `rustfmt` from this repo's
nixpkgs, and `just quality` runs `cargo fmt --check`, clippy with `-D warnings` and `cargo test`
on the crate. Picasso's `labs/rust-agent` (h0ffmann/picasso#142) replaces the dev shell's packages
once merged.

## Consequences

- We own the security of a proxy. The tests are the contract: a bug here can turn a volunteer's
  node into an open relay, so every refusal (other hosts, other ports, IP literals, `https://` in
  absolute form, origin-form requests) is tested end to end against the running server, as are the
  tunnel and the plain-HTTP forward.
- The allowlist is exact: a subdomain of an agency is not allowed unless it is in `hosts`.
- Bumping the Rust image is a `Dockerfile` edit (tag and digest), and its tests must pass in the build.
