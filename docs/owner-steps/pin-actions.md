# Pin the actions by commit SHA

An owner step. This branch may not edit `.github/`, so nothing here is applied. A tag can move: a SHA cannot.
The SHAs below are the ones Hermes resolved with the GitHub API on 2026-11-11 (the tag to its commit); they are
not checked again by this repo. Check each one against the action's release page before you apply it.

Dependabot with the `github-actions` ecosystem ([dependabot.yml](dependabot.yml)) keeps a pin and its `# tag`
comment current once the pins are in.

## Every `uses:` line in `.github/workflows/*.yml`

The line numbers are those of the checkout this draft was written from. The `actions/cache/restore` and
`actions/cache/save` lines use the SHA of the `actions/cache` repository, because a sub-action lives in the same
repository and tag. The same holds for the devkit's reusable workflows and its `bot-token` action: one repository,
one tag, one SHA.

| File and line | Now | Tag | SHA | Exact replacement |
|---|---|---|---|---|
| `board-schema.yml:23` | `actions/checkout@v7` | v7 | `3d3c42e5aac5ba805825da76410c181273ba90b1` | `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7` |
| `board-schema.yml:26` | `docker/login-action@v4` | v4 | `8aa5831fb8d48d8f76594c7ddde61ae58019f550` | `uses: docker/login-action@8aa5831fb8d48d8f76594c7ddde61ae58019f550 # v4` |
| `bump-ready.yml:15` | `marola-dev/marola-devkit/.github/workflows/notify-devkit.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/notify-devkit.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `ci.yml:20` | `marola-dev/marola-devkit/.github/workflows/static-ci.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/static-ci.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `ci.yml:36` | `marola-dev/marola-devkit/.github/workflows/python-ci.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/python-ci.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `ci.yml:50` | `marola-dev/marola-devkit/.github/workflows/agents-check.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/agents-check.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `gemini.yml:15` | `marola-dev/marola-devkit/.github/workflows/gemini-review.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/gemini-review.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `labels.yml:15` | `marola-dev/marola-devkit/.github/workflows/labels-sync.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/labels-sync.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `members.yml:23` | `actions/checkout@v7` | v7 | `3d3c42e5aac5ba805825da76410c181273ba90b1` | `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7` |
| `members.yml:28` | `marola-dev/marola-devkit/.github/actions/bot-token@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/actions/bot-token@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `notify-umbrella.yml:15` | `marola-dev/marola-devkit/.github/workflows/notify-umbrella.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/notify-umbrella.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `pr.yml:14` | `marola-dev/marola-devkit/.github/workflows/pr-body.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/pr-body.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `pr.yml:23` | `marola-dev/marola-devkit/.github/workflows/ci-short-circuit.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/ci-short-circuit.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |
| `site-health.yml:34` | `actions/checkout@v7` | v7 | `3d3c42e5aac5ba805825da76410c181273ba90b1` | `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7` |
| `site.yml:61` | `actions/checkout@v7` | v7 | `3d3c42e5aac5ba805825da76410c181273ba90b1` | `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7` |
| `site.yml:69` | `docker/login-action@v4` | v4 | `8aa5831fb8d48d8f76594c7ddde61ae58019f550` | `uses: docker/login-action@8aa5831fb8d48d8f76594c7ddde61ae58019f550 # v4` |
| `site.yml:99` | `actions/cache/restore@v6` | v6 | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` | `uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6` |
| `site.yml:131` | `actions/cache/save@v6` | v6 | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` | `uses: actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6` |
| `site.yml:219` | `cloudflare/wrangler-action@v4` | v4 | `953926a2e2182532811c01a25e53647d93bf07c0` | `uses: cloudflare/wrangler-action@953926a2e2182532811c01a25e53647d93bf07c0 # v4` |
| `site.yml:227` | `actions/upload-pages-artifact@v5` | v5 | `fc324d3547104276b827a68afc52ff2a11cc49c9` | `uses: actions/upload-pages-artifact@fc324d3547104276b827a68afc52ff2a11cc49c9 # v5` |
| `site.yml:241` | `actions/deploy-pages@v5` | v5 | `368f82528645a54fb793d4d04e342629a3f51346` | `uses: actions/deploy-pages@368f82528645a54fb793d4d04e342629a3f51346 # v5` |
| `skills.yml:16` | `marola-dev/marola-devkit/.github/workflows/skills-update.yml@v0.20.4` | v0.20.4 | `2d49d22212997581039acacd191465221d8bbf1e` | `uses: marola-dev/marola-devkit/.github/workflows/skills-update.yml@2d49d22212997581039acacd191465221d8bbf1e # v0.20.4` |

Result: 22 of 22 lines resolved; 0 not resolved.

## What the SHA does not cover

- The devkit's reusable workflows call other actions inside the devkit. Pinning the devkit by SHA pins the workflow
  file; the actions that file uses are pinned (or not) in the devkit's repository. [OPEN: read the devkit's
  workflows at that SHA and check that they pin their actions.]
- `ci.yml`, `gemini.yml` and `pr.yml` also pass `devkit-ref: v0.20.4` to the devkit, and `ci.yml` runs
  `git clone -b v0.20.4` on the devkit. `git clone -b` takes a tag or a branch, not a SHA, so those stay a tag
  unless the devkit's workflows accept a SHA. [OPEN: owners. The devkit's workflows were not read for this draft.]
  `flake.nix` holds the same tag as a flake input; `flake.lock` is committed (see AGENTS.md), so a tag bump
  also changes the locked rev there (`nix flake lock --update-input marola-devkit`).
- `ci.yml` says to bump the tag, the `devkit-ref` inputs and `flake.nix` together. With SHAs that is one more
  place to change, so a bump becomes: tag, SHA, `devkit-ref`, `flake.nix`.
- `.github/actionlint.yaml` is read by `actionlint` in `just quality`; apply the change, then run `just quality`.
