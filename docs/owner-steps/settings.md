# Repository settings: what to switch on, and one workflow to read

An owner step. These are repository settings and `.github/` files, which this branch may not change. This page
describes each one, what it costs and what it does not cover. It does not decide. Where a fact comes from a file
of this repository it names the file; where it is a belief about GitHub it says so.

## 1. Private vulnerability reporting

Settings, Code security, "Private vulnerability reporting": on. [SECURITY.md](../../SECURITY.md) and
`/.well-known/security.txt` (`app/Pages/Meta.fs`) already tell people to report at
`https://github.com/marola-dev/marola-front/security/advisories/new`. While the setting is off, that link does not
let a visitor report. This is the one setting the repository's own text depends on.

## 2. Secret scanning and push protection

Settings, Code security: "Secret scanning" and "Push protection": on. Push protection blocks a push that holds a
known token shape. The repository's rule is that no key is in code (AGENTS.md, "Org invariants"). The check that a
key never reaches a log is a test (`just server-test`, `scripts/server_smoke.sh`); nothing in this repository checks
the git history for secrets. Both settings are free on a public repository [INFERENCE: not checked for this one].

## 3. Branch protection on the default branch

Settings, Branches, a rule for the default branch (`main` in `ci.yml`):

- Require a pull request before merging, with at least 1 approval. Dismiss stale approvals on a new push.
- Require status checks to pass: `ci-ok`. It is the one check `ci.yml` says every marola repo requires, and it
  needs the other three jobs (`static`, `python`, `agents`). The reusable jobs report under names the devkit
  decides (`static / ...`); list those only after reading them in a finished run. [OPEN: owners. Which inner
  check names to require.]
- Require branches to be up to date before merging.
- Block force pushes and deletion of the branch.
- Optional: "Require review from Code Owners", once [CODEOWNERS.draft](CODEOWNERS.draft) has real names.
- Optional: apply the rule to administrators too. Cost: an owner cannot push a fix straight to `main`.

What a rule does not do: `ci.yml` does not run the F# tests, `just fp-audit` or `just design-check`. The F# gate
is `just quality`, which `just prepush` runs on a developer's machine. A required check named `ci-ok` therefore
does not prove the F# code passes. To make it a required check, a job that runs
`nix develop path:. -c just quality` has to be added to `ci.yml` and to the `needs` of `ci-ok`. [OPEN: owners.
`quality` downloads NuGet packages and needs a runner with Nix and the network; a cost decision.]

## 4. Signed commits

Settings, Branches, the rule above: "Require signed commits". Option, not a recommendation.

- Gain: a commit on `main` is tied to a key the author controls, so a stolen password or token alone cannot make
  a commit that looks like a person's.
- Cost: every author and every bot that pushes with `git` needs a signing key GitHub knows. The agents that work on
  this repository push with an installation token and unsigned local commits [INFERENCE from the workspace
  notes, not tested]; a merge strategy that keeps those commits (merge commit or rebase) would then be refused.
  Squash merge in the web UI makes a commit GitHub signs, so it passes. Dependabot commits are signed by GitHub.
- The repository's commit-trailer rule (`Tested:` and Co-Authored-By) is separate and unaffected.

## 5. Actions: `pull_request_target` in `gemini.yml`

What it is. The file `.github/workflows/gemini.yml` triggers on `pull_request_target` (type `review_requested`)
and passes `secrets: inherit` to the devkit's `gemini-review.yml`. `pull_request_target` runs the workflow file of
the base branch, with the repository's secrets and a token that can write, even when the pull request comes from a
fork. `pull_request` does not: a fork run gets no secrets and a read-only token.

Why it matters. That trigger is safe only while no job in the run executes text the pull request wrote. `gemini.yml`
passes `check-command: node scripts/site_check.js`. If the devkit's workflow checks out the pull request's code and
runs that command, then `scripts/site_check.js` comes from the pull request, and a fork can send its own copy
that reads the secrets. The workflow's comment says only a maintainer can request the team `gemini`, which means
a person has to start the run; it does not say what the run checks out. [OPEN: owners. Read
`gemini-review.yml` of the devkit at the pinned tag and see what it checks out, which secrets `inherit` passes
and what `check-command` runs on. It was not read for this draft.]

What could change (pick one, or none):

- Keep the trigger and make the run safe: never check out the pull request's head in a job that has secrets; run
  the check command in a separate job with no secrets and `permissions: {}`; pass the result as an artifact; let
  the job with secrets only post the review.
- Run the review only for pull requests from the same repository
  (`github.event.pull_request.head.repo.full_name == github.repository`) and say that fork pull requests get no
  Gemini review.
- Put the secret in an Actions environment that requires an owner's approval before a job can read it.
- Replace `secrets: inherit` with the one secret the job needs, so the others are not in the run.

Other workflows of this repository: `ci.yml` and `pr.yml` run on `pull_request` and set `permissions:
contents: read`. `ci.yml` sets `permissions: {}` on `ci-ok`. Pinning every action by SHA is in
[pin-actions.md](pin-actions.md).

## 6. What the drafts in this folder do

| File | Becomes | One line |
|---|---|---|
| [dependabot.yml](dependabot.yml) | `.github/dependabot.yml` | weekly pull requests for NuGet (every project with a lock file) and for Actions |
| [codeql.yml](codeql.yml) | `.github/workflows/codeql.yml` | CodeQL on the JavaScript; F# is not supported by CodeQL |
| [scorecard.yml](scorecard.yml) | `.github/workflows/scorecard.yml` | OpenSSF Scorecard on the repository's practices |
| [pin-actions.md](pin-actions.md) | edits to `.github/workflows/*.yml` | every `uses:` line and its SHA |
| [CODEOWNERS.draft](CODEOWNERS.draft) | `.github/CODEOWNERS` | owners for the paths that need one; names are `OPEN: owners` |
