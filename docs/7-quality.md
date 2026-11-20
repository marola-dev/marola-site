# Quality

What this repository measures about its own code, what it checks only by hand, and what nobody checks. It does
not rank the project against any other. Each row says how the practice is checked, where, and the result on
2026-11-12 (branch `claude/184-elm-haskell`, after the Elm and Haskell port replaced the earlier code).

How to read the **Result** column:

- **pass**: a command in this repository proves it. The command is in the row, and it was run for this page.
- **fail**: a command or a reading of a file shows the practice does not hold. The row says what.
- **unknown**: no command settles it, or the command was not run here. The row says which check would settle it.

A claim with no row on this page is not measured.

## Functional programming

The architecture rule (AGENTS.md, "What this repo is"): the Elm page is pure, and every effect leaves it as data
through a port to `front/ports.js`; the Haskell pages renderer reads its files in `Marola.Pages.Loader` and
`Marola.Pages.Build` and renders from values; the server keeps its effects in `IO`, in `back/server`.

| Practice | How checked | Where | Result today |
|---|---|---|---|
| The Elm page has no effect outside its ports | the language: Elm has no I/O but `Cmd` and ports | `front/src` | pass by construction. `front/ports.js` and `front/js/` are the only hand-written JavaScript |
| The port gives the same answers as the old JavaScript | `front/tests/golden.json`, written by the old code | `node scripts/golden.js --check`, `just front-test` (`GoldenTests`) | pass |
| The Elm page's state machine | elm-test | `just front-test` | pass: 68 tests |
| The page's effect shell works against the built output | a Node run with a fake DOM and a MapLibre stub | `node scripts/front_check.js` (after `just dist-build --fixtures`) | pass: 137 assertions |
| The static pages do not change byte for byte | a compare with another build | `scripts/pages_parity.sh <dir>` | pass: 23 of 23 against the earlier renderer's build at efaaea3 (with b8cb19e's rename), before `humans.txt` named Elm and Haskell |
| Warnings | `-Wall` in both `.cabal` files; not an error | every `cabal build` | not enforced: a warning does not fail the build |

## Security

| Practice | How checked | Where | Result today |
|---|---|---|---|
| Every response carries the security headers: on 200, 404, HEAD, 405, 500, a 429 and a 413 | a test on the real pipeline | `just back-test` (`HeaderSpec`, `LimitSpec`) | pass: 128 server examples |
| The CSP has no `unsafe-*`, no wildcard, only the known origins; scripts, styles and workers from `self` | the built page's `<meta>` against `dist/csp.txt` (`marola-server csp`) | `node scripts/front_check.js` | pass |
| A 500 shows no stack trace or detail; the log keeps the cause | a test | `just back-test` (`HeaderSpec`) | pass |
| Rate limits: the contact form (10 in 10 minutes), the general limit, `X-Forwarded-For` only from the loopback, the API key (30 a minute), 1 submission per account every 10 minutes and 10 a day | tests | `just back-test` (`LimitSpec`, `StudyApiSpec`) | pass. The per-key limiter is in memory: a restart resets it |
| Sessions: 12 hours absolute, only a hash stored, a state that does not replay; CSRF token bound to the session; a post without the token is a 403 and stores nothing | tests | `just back-test` (`SessionSpec`, `LoginSpec`, `WebSpec`, `StudyApiSpec`) | pass |
| The PDF intake: magic and tail, active-content names (also `#xx` escaped), an `/OpenAction` with an action, object streams, an encrypted file, a bomb with bounded memory, the size limit while streaming, the quota | tests on real small PDFs | `just back-test` (`PdfSpec`) | pass. Not covered: plain streams are not scanned, and a bug in a PDF viewer ([ADR 0004](adr/0004-study-submission.md)) |
| Study text is escaped on every page (`<script>` and `"onmouseover=` in every field) | tests | `just back-test` (`WebSpec`) | pass |
| No key, token, client secret, address, email, query or body in the log | tests and a smoke run of the built server against a fake GitHub | `just back-test`, `scripts/server_smoke.sh` | pass |
| The API's document lists every `/api/v1` route and the validation's limits | tests that read the real route table | `just back-test` (`OpenApiSpec`) | pass |
| Packages are pinned | `front/package-lock.json` (npm, with hashes), `front/elm.json`, `cabal.project.freeze` (versions and `index-state`, no hashes) | `just front-test`, `just back-test` | pass for npm and Elm (exact versions); the freeze pins versions, not hashes, and the Nix build does not read it ([5-hosting](5-hosting.md#build-with-nix)) |
| No npm package has a known vulnerability | `npm audit` in `front/` | `just audit` (by hand, needs network; not in `just quality`) | unknown: not run on this branch. The npm packages are build tools only; nothing from npm reaches the browser. No audit covers the Haskell or Elm packages |
| The vendored `MEMBERS.md` is the blob the pin names | a hash compare | `just members-check`, part of `just quality` | pass |
| The design tokens and `style.css` agree; no stray colour | a script with a self-test | `just design-check` | pass |
| No JavaScript that Elm or Haskell could be (ADR 0007) | every tracked JavaScript file against `scripts/js-allowlist.tsv`, each line with its reason | `just js-check`, part of `just quality` and CI's `back` job | pass: 23 files, 7 of the new site (ports, the two MapLibre/WebGL glue files, Vite's config, the vendored libraries, `front_check.js`, `basemap_style.mjs`) and the legacy page's, which go at the cutover |
| The phone nav strip does not scroll sideways | a real browser's layout | `CHROMIUM=... scripts/nav_measure.sh` | unknown: needs a Chromium; not run here, and not part of `just quality` |
| The built site is the same bytes on two runs | `nix build --rebuild` | `just nix-build` | unknown: the Nix package for Elm and Haskell has not been built (its npm and Elm hashes are placeholders). `security.txt` holds the build day in `Expires`, so builds on two days differ in that one file |
| The git hook scripts do not touch another repository when git exports `GIT_DIR` | a self-test | `scripts/mip-trailer-check.sh --self-test`, part of `just quality` | pass |
| `AGENTS.md`'s invariants block is the org's | a byte compare with the devkit's block | `agents-check`, part of `just quality` | pass. It checks that block only |
| Docs have no stale wording and no foreign recipe | a linter | `docs-lint`, part of `just quality` | pass |
| npm and Actions updates arrive as pull requests | none in the repository | owner step 1 | fail: no `dependabot.yml` ([owner-steps](owner-steps/dependabot.yml)) |
| Static analysis of the Elm and Haskell code | none. CodeQL supports neither language | [owner-steps/codeql.yml](owner-steps/codeql.yml) covers the JavaScript only | fail: nothing analyses `front/src` or `back/` for vulnerabilities except the compilers (`-Wall` on both Haskell packages) and the tests. A fuzz test or a penetration test has not been done |
| Actions are pinned by commit SHA | `grep -hn "uses:" .github/workflows/*.yml \| grep -vc '@[0-9a-f]\{40\}'` | `.github/workflows/` | fail: 22 of 22 `uses:` lines use a tag ([pin-actions.md](owner-steps/pin-actions.md)) |
| Private vulnerability reporting, secret scanning, push protection and branch protection are on | repository settings; nothing in the repository reads them | GitHub settings | unknown. An owner reads the settings page ([settings.md](owner-steps/settings.md)) |
| The Elm and Haskell gate runs on every pull request | reading `.github/workflows/ci.yml` | `.github/workflows/ci.yml` | pass since 2026-11-12: `ci.yml` has the jobs `back` (ormolu, `cabal build all`, `cabal test all`), `front` (elm-format, `npm test`, `site_build.sh --fixtures`, `front_check.js`) and `smoke` (`server_smoke.sh`), all in `ci-ok`. `static` runs `golden --check`, `design-check` and `members_vendor_check.sh`. Not run in CI: `just quality` as a whole. The devkit's `static-ci.yml` was not read. Not run on a runner yet ⚠ |
| A researcher knows how to report a flaw | [SECURITY.md](../SECURITY.md) and `/.well-known/security.txt` | `just back-test` (`MetaSpec`) checks `security.txt`; the policy text is by hand | pass for `security.txt`; unknown for the policy until private reporting is on (above) |

## Agent harness

What lets an agent work here without reading all the code.

| Practice | How checked | Where | Result today |
|---|---|---|---|
| `AGENTS.md` is accurate: every path, recipe and rule it names exists and is true | `agents-check` compares only the invariants block | by hand | unknown. A script that checks that each backticked path exists and each `just` recipe named is in `just --summary` would settle the commands and paths |
| `skill.md` (the API guide for agents) is served and has the endpoint, the dry run, the levels and no key | a test; a smoke run | `just back-test` (`StudyApiSpec`), `scripts/server_smoke.sh` | pass |
| Every error code `skill.md` lists has a message in both languages and a place in the OpenAPI enum | tests | `just back-test` (`WebSpec`, `OpenApiSpec`) | pass |
| The OpenAPI document is served, is 3.1, is cached 300 s, and matches the route table and the validation limits | tests and a smoke run | `just back-test` (`OpenApiSpec`), `scripts/server_smoke.sh` | pass |
| `llms.txt` lists the areas, the pages, the API documents and the board contract | tests | `just back-test` (`MetaSpec`) | pass |
| One entry point: the `just` recipes | AGENTS.md lists them; `just --list` | `justfile` | unknown whether every recipe is listed in AGENTS.md. Comparing `just --summary` with the file would settle it |
| Tests are the oracle: one command runs every gate that needs no docker | `just quality` | `justfile` | unknown on this branch: `just quality` was not run whole here (no `agents-check`, `docs-lint`, `ruff` or `actionlint` in this sandbox). It includes the Elm and Haskell tests, the smoke self-tests, `agents-check` and `docs-lint` |
| Hooks run the same gate | the devkit's hooks call `just precommit` and `just prepush`; the dev shell sets `core.hooksPath` | `justfile`, `.devkit/` | unknown for a fresh clone: no check that the hooks are installed. Running `git config core.hooksPath` after `nix develop` in a new clone would settle it |
| A stale generated file fails a check and says how to regenerate | `--check` modes; the table in AGENTS.md ("Never edit by hand") | `just quality` (`golden`, `i18n_bundle`, `news_build`, `members-check`) | pass for `golden`, `i18n_bundle` and `news_build` (`--check` in `just quality`); the members block is checked by `members_build.py --check` in `ci.yml` and by `just members-check` in `just quality`. The Nix hashes (`npmDeps`, `nix/elm-srcs.nix`) have no check in `just quality` |
| A generated file says it is generated | the first lines of the file | `site/static/i18n.js`, `site/static/news.html` | pass for these two (`do not edit` in their headers). Not checked for the others |
| The build is hermetic: no network in the build | the Nix sandbox | `just nix-build`, `just package-smoke` | unknown: the Elm and Haskell package has not been built ([5-hosting](5-hosting.md#build-with-nix)) |
| The commit rules (`Tested:`, Co-Authored-By, `MIP:` on a legacy change) | a hook and its self-test | `scripts/mip-trailer-check.sh`, `just prepush` | pass for the self-test; the trailers on `Tested:` and Co-Authored-By are by hand |

## Proof of this page

On 2026-11-12, outside `nix develop` (GHC 9.6.6, cabal 3.12, elm 0.19.1, node 22):

```
cabal test all && (cd front && npm test) && scripts/site_build.sh --fixtures && node scripts/front_check.js \
  && scripts/server_smoke.sh && node scripts/golden.js --check && just design-check
```

exit 0. Test counts: `back/pages` 102 examples, `back/server` 128, elm-test 68. `front_check`: 137 assertions,
0 failed. `server_smoke`: 0 failures, 20 MB resident after start.

## Owner steps

Things this branch cannot do, because `.github/` and the repository settings are off limits to it. Each draft is in
[owner-steps/](owner-steps/settings.md); copy it, read it, change it. None of them is applied.

1. **Dependabot.** Copy `docs/owner-steps/dependabot.yml` to `.github/dependabot.yml`. After an npm bump a person
   updates `npmDeps`'s hash in `nix/package.nix` (the failing `nix build` prints it).
2. **Pin the actions.** Apply the 22 replacement lines of [pin-actions.md](owner-steps/pin-actions.md) to
   `.github/workflows/*.yml`. The SHAs are Hermes's of 2026-11-11.
3. **CodeQL.** Copy `docs/owner-steps/codeql.yml` to `.github/workflows/codeql.yml`. It analyses the JavaScript only;
   Elm and Haskell are not supported by CodeQL.
4. **Scorecard.** Copy `docs/owner-steps/scorecard.yml` to `.github/workflows/scorecard.yml`. Decide first whether
   to publish the result.
5. **Run the rest of the gate in CI.** The Elm and Haskell jobs exist (`back`, `front`, `smoke`); `design-check` and
   `golden --check` do not run there yet. OPEN: owners.
6. **CODEOWNERS.** Copy `docs/owner-steps/CODEOWNERS.draft` to `.github/CODEOWNERS` and write real names for the
   five paths. OPEN: owners.
7. **Repository settings.** Private vulnerability reporting on (SECURITY.md and `security.txt` depend on it), secret
   scanning and push protection on, branch protection on the default branch with `ci-ok` as a required check, no
   force push, reviews. Signed commits are an option with a cost. All in [settings.md](owner-steps/settings.md).
8. **`gemini.yml`.** Read what the devkit's `gemini-review.yml` checks out under `pull_request_target`, and decide
   among the changes in [settings.md](owner-steps/settings.md#5-actions-pull_request_target-in-geminiyml).
9. **Build the Nix package once with network.** `just nix-build` fails on each `lib.fakeHash` (`npmDeps` in
   `nix/package.nix`, each entry of `nix/elm-srcs.nix`) and prints the real hash; copy them in, then run
   `just package-smoke` and check that piabrota/nix-os's nixpkgs builds the Haskell dependencies.
