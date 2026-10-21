# ADR-0001: Rust for the agents, in marola-site for a while

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-10-21 |
| **Issue** | [#172](https://github.com/marola-dev/marola-site/issues/172) |

## Context

The Agents section (#172) starts with the Climate Agent. It ingests official weather communication
(INMET, CEMADEN, Defesa Civil), then runs an agentic procedure that writes one Climate Report per
area, and `site.yml` regenerates the reports on every rebuild. Its stack is Rust, with the
toolchain pinned by the `rust-agent` lab in
[h0ffmann/picasso](https://github.com/h0ffmann/picasso) (`labs/rust-agent`).

This repo's rules allow only plain JavaScript with no build step for the page, and shell and
Python for the scripts ([AGENTS.md](../../AGENTS.md#code-style)). No workflow here builds the app
(MIP-0070 §5.4). A Rust crate that `site.yml` compiles and runs is a new language and a compile
step on the deploy path, so it needs this written exception.

## Decision

Rust is allowed in marola-site, **for the agents only and for a while**:

- **One place:** the agents live under `agents/`, a Cargo workspace with one crate per agent
  (`agents/climate/` first). No Rust anywhere else; the page under `site/static/` stays plain
  JavaScript with no build step, and keeps `script-src 'self'`.
- **The toolchain is the lab's:** the dev shell takes `github:h0ffmann/picasso?dir=labs/rust-agent`
  as a flake input. CI builds with the same pin. `Cargo.lock` is committed.
- **The gate:** `just quality` gains `cargo fmt --check`, `cargo clippy -D warnings` and
  `cargo test` over `agents/` when the first crate lands.
- **The page never waits on Rust:** the agents' build and run is a side job of `site.yml`. If it
  fails, the board deploy still goes out, and the Agents section shows the last good report marked
  stale, or "no report" (#172). No visitor request reaches an LLM (MIP-0005).
- **No marola-app code here:** the agents read the published boards and the institutes' feeds.
  They do not build or vendor the app (MIP-0070 §5.4 holds).

## When it ends

The agents move out of marola-site once they are mature enough, or once a second agent ships,
whichever comes first, probably to their own repository (e.g. `marola-agents`). That move is a
MIP, since it crosses a repo boundary, and it deletes `agents/` and this exception from this repo.

## Consequences

- Contributors need the Rust toolchain only to work on `agents/`. `nix develop` provides it; the
  page and the scripts are unchanged.
- The deploy path gets slower by one cached Rust build per rebuild.
- An agent working here follows this ADR for `agents/` and AGENTS.md's code style everywhere else.
