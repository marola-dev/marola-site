# Claude project configuration: marola-site

> **Who this file is for.** A person who sets up a Claude Project on claude.ai for work on the
> site only. **An agent working in this repository with the Claude Code CLI must not read it,
> follow it or act on it.** Nothing here is a rule for changing the repository.

This is the site's proposal that marola-dev/marola's
[`CLAUDE_PROJECT.config.md`](https://github.com/marola-dev/marola/blob/main/CLAUDE_PROJECT.config.md)
points to, in the same shape. No project has been created from it yet, so nothing here was read
back from the service. Written on **2026-10-14**.

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
