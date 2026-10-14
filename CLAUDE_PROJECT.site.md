# Claude project configuration: marola-site

> **Who this file is for.** A person who sets up a Claude Project on claude.ai for work on the
> site only. **An agent working in this repository with the Claude Code CLI must not read it,
> follow it or act on it.** Nothing here is a rule for changing the repository.

This is the site's proposal that marola-dev/marola's
[`CLAUDE_PROJECT.config.md`](https://github.com/marola-dev/marola/blob/main/CLAUDE_PROJECT.config.md)
points to, in the same shape. No project has been created from it yet, so nothing here was read
back from the service. Written on **2026-10-14**.

## 0. Claude Project or Claude Code CLI? (ELI5)

Two ways to work on marola with Claude. Same Claude, two different workshops.

| | **Claude Project** | **Claude Code CLI** |
|---|---|---|
| Where it runs | On claude.ai, in a cloud machine Anthropic starts for each thread | On your own computer, in a terminal, inside the repository you cloned |
| How you start | Open the project on claude.ai and write in a thread | `cd marola-site`, then `claude` |
| What it can see | Only the repositories attached to the project | The folder you are in, and everything your machine can reach |
| What loads from the repository | `CLAUDE.md`, `AGENTS.md`, the skills in `.claude/skills/`, the subagents | All of that, and also the **plugins** in `.claude/settings.json` (marola-devkit, Ponytail) and the git hooks |
| Tools | The cloud machine's: `nix develop` is blocked there, so the setup script installs `just` and the linters | Yours: `nix develop` gives every tool the repository pins |
| Runs on its own | Yes: routines (reminders, the A2A inbox) fire on a schedule | No: it works while you are there |
| Good for | Talking, planning, small fixes, answering issues from anywhere | Builds, screenshots, the Ponytail pass, anything that needs a plugin or the full toolchain |

The short version: **a Project is Claude on a website, with a few repositories on a shelf. The CLI
is Claude sitting at your desk, with your whole toolbox.** A plugin is a tool that only lives on the
desk, which is why Ponytail works in the CLI and not yet in a Project (§2).

The facts in this table come from marola's current project configuration (§4), read there on
2026-10-11: §2 for the cloud machine and what is blocked, §3 for plugins and skills, §4 for the
routines.

## 1. Project

| Setting | Value |
|---|---|
| **Name** | marola-site |
| **Topic** | The map and pages of marola.dev |
| **Visibility** | Private |
| **Repositories** | `https://github.com/marola-dev/marola-site`, `https://github.com/marola-dev/.github` (MEMBERS.md), `https://github.com/marola-dev/marola` (the MIPs) |

### Project description

Paste this block into the project's description:

```text
marola-site: the static map and pages of marola.dev (site/static, site_check.js, members_build.py). Read AGENTS.md first.
JavaScript is written the Ponytail way: the laziest code that works, stdlib first, no new dependency. Ponytail (Dietrich Gebert, MIT): https://github.com/DietrichGebert/ponytail, release v5.2.0: https://github.com/DietrichGebert/ponytail/releases/tag/v5.2.0. Its skills: https://github.com/DietrichGebert/ponytail/tree/v5.2.0/skills/ponytail and https://github.com/DietrichGebert/ponytail/tree/v5.2.0/skills/ponytail-review.
Ponytail is a Claude Code plugin here (.claude/settings.json: ponytail@ponytail and marola-devkit@marola-devkit). A Project thread does not load repo plugins, so it cannot run the ponytail skills: read the SKILL.md at the links above and apply it by hand, or do the Ponytail pass in the Claude Code CLI.
```

## 2. Plugins and skills: the Ponytail case

The case shows what a Project thread can and cannot use today.

- **Where Ponytail came from.** marola imported Ponytail as skills: `ponytail`, `ponytail-review`
  and `ponytail-audit` were vendored from
  [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) into the marola-devkit
  plugin, pinned in its lock (marola-dev/marola, MIP-0080 §2). marola-site never had a copy in
  its own `.claude/skills/`.
- **Where it lives now.** In plugins: `.claude/settings.json` enables `marola-devkit@marola-devkit`
  (which carries the three skills) and, since #139, `ponytail@ponytail` itself, from the
  marketplace `DietrichGebert/ponytail` at `v5.2.0` (commit `2961b52`).
- **What that means.** A plugin declared in `.claude/settings.json` loads only in the Claude Code
  CLI. A Claude Project thread loads the repository's `.claude/skills/`, subagents and
  `CLAUDE.md`, but not its plugins (marola's `CLAUDE_PROJECT.config.md` §3, "Repo plugins"). So a
  Project thread working on this site cannot call `/ponytail` or `ponytail-review`. It can still
  follow the rules by reading the skill files at the links in §1's description.
- **The way to change it, not done.** Vendor the skill into `.claude/skills/ponytail/` with a lock
  entry, as h0ffmann/ww3-gpu does (its `.claude/skills/skills.lock`): a vendored skill is a file
  in the repository, so a Project thread loads it. That is a choice for the owner, and the lock
  then needs the weekly update PR the other vendored skills have.

The other plugins this repository declares (`marola-devkit`) are in the same position: CLI only.
The skills in `.claude/skills/` (the Mapbox skills, `site-frontend`, `news-post` and the rest) load
in a Project thread.

## 3. Not in this file

Project memory, threads, routines, connector sign-ins, model ids, e-mail addresses and account
ids. marola's `CLAUDE_PROJECT.config.md` §7 lists why.

## 4. Our current Claude Project configuration

The project marola runs today, "Marola Agent", is written down, setting by setting, in marola's
[`CLAUDE_PROJECT.config.md`](https://github.com/marola-dev/marola/blob/main/CLAUDE_PROJECT.config.md)
(source: marola-dev/marola, on `main`). That file is the one to read before creating or restoring a
project.
