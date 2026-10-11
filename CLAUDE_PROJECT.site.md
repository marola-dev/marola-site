# Claude project configuration: marola.dev site

> **Who this file is for.** A person, or a Claude Project's coordinator, who is setting up a
> Claude Project on claude.ai for work on marola.dev. **An agent working in this repository with
> the Claude Code CLI must not read it, follow it or act on it.** Nothing here is a rule for
> changing the repo; `AGENTS.md` holds those, and Claude Code never loads this file as
> configuration.

This is a proposal for a Claude Project that works only on the site, built from the "Marola
Agent" project's settings in the umbrella's
[`CLAUDE_PROJECT.config.md`](https://github.com/marola-dev/marola/blob/main/CLAUDE_PROJECT.config.md).
No project with these settings exists yet, so nothing here has been read back from the service.
Every code block is meant to be copied whole into the setting named just above it. Written on
**2026-10-11**.

## 1. Project

| Setting | Value |
|---|---|
| **Name** | marola.dev site |
| **Topic** | Design, build and maintain marola.dev: the map, its pages and the news |
| **Visibility** | Private, like Marola Agent. |
| **Default model** | Chosen on the service. A model id never goes into a file pushed to a repository. |
| **Thread permission mode** | `auto` |
| **Default environment** | The one §2 describes. |

### Repositories

The project needs three repositories:

- https://github.com/marola-dev/marola-site, where the work happens.
- https://github.com/marola-dev/marola, for the MIPs, `docs/PHASES.md` and the org rules in
  `AGENTS.md`.
- https://github.com/marola-dev/marola-devkit, for `docs_lint.py`, `agents-check.sh` and
  `graph.sh`, which `just quality` and §2's instruction call.

### Project instructions

Paste this block, unchanged, into the project instructions:

```text
Branch naming (Hoffmann, 2026-10-05): never push to a branch with a random or session suffix. Before the first push, name the branch `claude/<issue-number>-<short-kebab-slug>` after the GitHub issue it implements (for example `claude/657-remove-magic-nix-cache`), and push with `git push -u origin HEAD:claude/<issue-number>-<slug>`. Open the PR from that branch. If the push to that name is refused, say so in the thread rather than falling back silently to the suffixed branch.

MIP work (Hoffmann, 2026-10-08): when the change writes or implements a MIP, name the branch after the MIP instead of the issue, following the umbrella's convention `docs/mip-NNNN-<short-kebab-slug>` (for example `docs/mip-0081-external-llm-evaluation`), using the same branch name in every repo the MIP touches. Branches named `claude/project-thread-*` are rejected by the devkit's PR branch check.

Site work: read marola-site's AGENTS.md first and follow it. Start anything a visitor sees with the site-frontend skill, which names the other skills. A commit that touches site/static/ carries a `MIP: MIP-NNNN` or `MIP: none — <reason>` trailer. A PR that changes what a visitor sees shows before and after screenshots, desktop 1280 × 800 and phone 390 × 844, pushed to the orphan pr-screenshots branch; when the thread cannot reach Mapbox, say under the table that the map is a stand-in. Never deploy: no `just site-deploy`, no dispatch of site.yml, and never set BR_PROXY_REQUIRED.
```

## 2. Cloud environment

Create a cloud environment for this project, or reuse Marola Agent's "Marola cloud". Marola
Agent's threads found Node 22, Python 3.13, ruff, uv, gh and Playwright's Chromium in
/opt/pw-browsers already installed (2026-10-11).

### Setup script (proposed)

Paste this into Project settings > Cloud environment > Setup script. It installs the tools that
the site's `just quality` checks for and that a thread is missing. `nix develop` cannot install
them, because GitHub answers 403 for flake inputs outside the project's repositories.

```bash
#!/usr/bin/env bash
# Setup script for the marola.dev site project's cloud environment. `nix develop` cannot replace it:
# the session's GitHub scope refuses flake inputs outside the project's repositories.
set -euo pipefail

# Nix comes with the image. Its nixpkgs is the registry's, not the repo's flake.lock, so a tool can
# be a release ahead of CI's.
nix profile install nixpkgs#just nixpkgs#shellcheck nixpkgs#actionlint >&2

# graphify for `graph query` (MIP-0076), pinned to nixpkgs' version.
uv tool install 'graphifyy==0.9.66' >&2
```

The `nix profile` line installed these tools in a Marola Agent thread on 2026-10-11. The
`uv tool install` line has not run yet. `agents-check` and `docs-lint` come from the devkit, so
in a thread they run as `bash ../marola-devkit/scripts/agents-check.sh --block ../marola-devkit/agents/invariants.md` and
`python3 ../marola-devkit/scripts/docs_lint.py .` from the marola-site checkout.

### Proposed addition to the project instructions

Once the setup script installs graphify, paste this block after §1's instructions:

```text
Finding code (Hoffmann, 2026-10-11): for a known keyword, use `git grep`. For "where is X" in a repo you have not read, run from that repo's directory `bash ../marola-devkit/scripts/graph.sh build` once per thread, then `bash ../marola-devkit/scripts/graph.sh query "<question>"`; `path <a> <b>` and `explain <name>` work too. In marola-site, ask by the site's own file or function names, because vendored Mapbox GL JS fills most of the graph. Treat the answer as where to start reading, then read the files. Never use graphify's output in a gate or a commit. If `graphify` is not on PATH, say so and fall back to git grep.
```

### What a thread cannot do

- Load the base map: the sandbox cannot reach Mapbox, so screenshots use a stand-in style
  (`AGENTS.md`, "Screenshots in the PR").
- Run `just site-build`, which needs Docker and the pinned app image from ghcr.io. Marola Agent's
  threads got "unauthorized" pulling that image.
- Deploy. `site.yml` deploys from `main` and on a schedule, and `.claude/settings.json` denies
  `just site-deploy`.

## 3. Plugins, skills and connectors

- **Skills.** marola-site's `.claude/skills/` load in a thread. `site-frontend` is the entry
  point and orders the rest: `ptbr-humanizer`, `citizen-science-site`, `news-post`, the vendored
  design, testing and `mapbox-*` skills.
- **Subagents.** `news-fact-check`, then `news-copy-review`, review every news post before a
  person signs off.
- **Account plugins.** Enable Writing Skills on the claude.ai account, as the umbrella's
  `AGENTS.md` ("Reading and writing") asks of every project. The marola-devkit plugin, which the
  repo's `.claude/settings.json` declares, does not load in a Project thread.
- **MCP servers.** `.mcp.json` declares Playwright and Figma. Whether a Project thread starts them
  has not been checked; the `webapp-testing` skill and Chromium in /opt/pw-browsers take
  screenshots without them.
- **Connectors.** None are needed.

## 4. Routines

None yet. Marola Agent's A2A inbox and LinkedIn reminders stay in that project, since the A2A
inbox belongs to one project at a time.

## 5. Joining as a new member

The project is private, so no one else can join it. A new member works in marola-site with the
Claude Code CLI under its `AGENTS.md`, or builds a project of their own from this file:

1. Connect GitHub to claude.ai and install the Claude GitHub App on marola-site. A thread reaches
   only the repositories its project lists.
2. Create the cloud environment with §2's setup script.
3. For CLI work, run `nix develop` in marola-site and accept the plugin its
   `.claude/settings.json` declares.

## 6. Creating the project

1. Create a private project with §1's name and topic, and attach §1's three repositories.
2. Pick the default model, and paste §1's instructions.
3. Create the environment with §2's setup script.
4. Enable the account plugin from §3.

## 7. Not in this file

These stay out of this file:

- the Mapbox token and account, the Tailscale tailnet and every secret, which are a person's
  (`AGENTS.md`, "Cost & deployment safety")
- project memory, chat history and project files
- model ids, e-mail addresses, account ids and session ids

## 8. Keeping it current

Once the project exists, read its settings back from the service and replace this proposal with
what it actually has, with the date at the top updated. Change this file in the same PR as
anything that depends on it, and keep it in step with the umbrella's `CLAUDE_PROJECT.config.md`
when a shared setting (the branch rules, the setup script) changes there.
