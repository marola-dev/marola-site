# Quality

What this repository measures about its own code, what it checks only by hand, and what nobody checks. It does
not rank the project against any other. Each row says how the practice is checked, where, and the result on
2026-11-11 (branch `hermes/gleam-maplibre-v2`, from commit 534ce36, with the working tree of run C4b-2).

How to read the **Result** column:

- **pass**: a command in this repository proves it. The command is in the row, and it was run for this page.
- **fail**: a command or a reading of a file shows the practice does not hold. The row says what.
- **unknown**: no command settles it, or the command was not run here. The row says which check would settle it.

A claim with no row on this page is not measured.

## Functional programming

The architecture rule (AGENTS.md, "What this repo is"): `Shared`,
`Client/Core` and `Pages` are pure code, with no I/O; effects sit in `Server` and `Client/App`. Pure code compiles
on .NET and on Fable, so the same tests run on both.

| Practice | How checked | Where | Result today |
|---|---|---|---|
| No effectful construct is added without a visible decision | a script: `mutable`, `null`, `raise`/`failwith`, `.Result`, `.Wait(`, `Async.RunSynchronously`, `unbox`, `downcast`/`:?>` and ref cells, per project, against a baseline; a count that goes up, or down without `--update`, fails | `just fp-audit` (`scripts/fp_audit.js`, `docs/fp-baseline.json`) | pass: every count equals the baseline. The baseline is the first measurement, not a goal |
| The counter counts what it says | a self-test on a bad fixture and on comments, strings and identifiers that must count as nothing | `node scripts/fp_audit.js --self-test` (runs inside `just fp-audit`) | pass: 25 cases |
| `Shared`, `Client/Core` and `Pages` do no I/O | by hand: a search of the three projects for `System.IO`, `File.`, `Directory.`, `HttpClient`, `DateTime.Now`, `Random`, `Environment.`, `Console.` and `printf` | see "Where the effects live" below | fail: one file, `app/Pages/Loader.fs`, reads files. No check keeps this true; the audit does not see I/O |
| Pure code has no `null`, no exception, no blocking call | `just fp-audit` | the three pure projects | pass: 0 for `null`, `raise`/`failwith`, `.Result`, `.Wait(`, `unbox`, `downcast` and ref cells. They hold 6 `mutable` in all (see below) |
| A data error is a `Result` or an `option`, not an exception | by hand | AGENTS.md ("Code style") | unknown. `just fp-audit` counts 10 `raise`/`failwith` in `Server` and 1 in `Client/App`; whether each is a data error is not checked. A reading of each site would settle it |
| The same pure code gives the same answers on .NET and on Node (Fable) | Expecto on .NET and the same tests compiled by Fable | `just app-test` | pass: 181 tests on .NET, 181 on Node |
| The F# port gives the same answers as the old JavaScript | `app/Tests/golden.json`, written by the old code | `node scripts/golden.js --check`, part of `just app-test` | pass |
| Format, and warnings are errors | Fantomas; `TreatWarningsAsErrors` in `app/Directory.Build.props` | `just app-fmt --check`; every build | pass |
| The client's effect shell works against the compiled output | a Node run with a fake DOM and a MapLibre stub | `node scripts/client_check.js` (after `just app-build --fixtures`) | pass: 131 assertions |

### Where the effects live

Numbers are from `just fp-audit` (`docs/fp-baseline.json`). Lines of code are in the table that script prints.
The audit blanks comments and strings first, and it does not see I/O, only the constructs above.

**`app/Shared`** (domain types, the board decoder, the study validation and its JSON writer) is pure by design and
compiles for .NET and Fable. It has 3 `mutable` (`Html.fs`:33-34, `Icu.fs`:69) and nothing else. Each is a local
cursor in a loop, read by hand. The numbers support the rule.

**`app/Client/Core`** (the model, `update`, the views as a virtual DOM, `Vdom.diff`) returns commands as data and
runs nothing. It has 1 `mutable` (`Params.fs`:42, a loop index). The numbers support the rule.

**`app/Pages`** (the renderer of the static pages, the Markdown subset, `Layout`, `Meta`) takes its input as values.
It has 2 `mutable` (`Markdown.fs`:49-50, the parser's position and error). The numbers support the rule, but the
rule does not hold: `Loader.fs` reads `site/i18n`, `site/content`, `MEMBERS.md`, `areas.json` and the avatar folder
with `File.ReadAllText`, `File.Exists`, `Directory.GetFiles` and `Directory.Exists`. It is the one file of the
three pure projects that breaks the rule. Every other file in `Pages` renders from what `Loader` returns. Moving
`Loader.fs` out of `Pages`, next to its callers (`Pages.Build`, `Server` and the test support), would make the rule
true; this run did not do that.

**`app/Server`** (ASP.NET Core, SQLite, the PDF intake, sessions, the board's commands) is where the effects belong:
the clock, the disk, the database, the network and the request. It has 35 `mutable`, 9 `null`, 10 `raise`/`failwith`
and 9 `downcast`. A plain search finds `mutable` on 25 lines of `PdfIntake.fs` (the streaming scanner keeps its
state in locals) and on 7 of `StudyApi.fs`. The `null` and `downcast` counts are the edge with ASP.NET and
`Microsoft.Data.Sqlite`, which return null and untyped values. The numbers do not contradict the rule; they also do
not show that the 10 raises are all unreachable or all non-data errors (the one in `StudyApi.fs` is marked
`unreachable`).

**`app/Client/App`** (the Elmish loop, the DOM patching, the ports to MapLibre) is the client's effect shell. It is
small: 259 lines, with 1 `raise`/`failwith` (`Dom.fs`:119, a path with no parent), 1 `unbox` (`Dom.fs`:30), 2
`downcast` (`Dom.fs`:114, 133) and 1 ref cell (`Program.fs`:19). The numbers support the rule, and they show the
casts of the DOM sit in one file.

**`app/Pages.Build`** is a build tool, not part of the rule. It has 1 `.Result` (`Program.fs`:33, a blocking fetch of
`MEMBERS.md`), which is fine for a program that exits.

**The test projects** are counted apart, in `fp-baseline.json` too. `Server.Tests` has the blocking calls (18
`.Result`, 2 `.Wait(`), because a test starts the server and waits for it. That is a test's right.

## Security

| Practice | How checked | Where | Result today |
|---|---|---|---|
| Every response carries the security headers: on 200, 404, HEAD, 405, 500, a 429 and a 413 | a test on the real pipeline | `just server-test` (`HeaderTests`, `LimitTests`) | pass: 128 tests |
| The CSP has no `unsafe-*`, no wildcard, only the known origins; scripts, styles and workers from `self` | a test of `Csp.policy` | `just app-test` (`CspTests`) | pass |
| A 500 shows no stack trace or detail; the log keeps the cause | a test | `just server-test` (`HeaderTests`) | pass |
| Rate limits: the contact form (10 in 10 minutes), the general limit, `X-Forwarded-For` only from the loopback, the API key (30 a minute), 1 submission per account every 10 minutes and 10 a day | tests | `just server-test` (`LimitTests`, `StudyApiTests`) | pass. The per-key limiter is in memory: a restart resets it |
| Sessions: 12 hours absolute, only a hash stored, a state that does not replay; CSRF token bound to the session; a post without the token is a 403 and stores nothing | tests | `just server-test` (`SessionTests`, `LoginTests`, `WebTests`, `StudyApiTests`) | pass |
| The PDF intake: magic and tail, active-content names (also `#xx` escaped), an `/OpenAction` with an action, object streams, an encrypted file, a bomb with bounded memory, the size limit while streaming, the quota | tests on real small PDFs | `just server-test` (`PdfTests`) | pass. Not covered: plain streams are not scanned, and a bug in a PDF viewer ([ADR 0004](adr/0004-study-submission.md)) |
| Study text is escaped on every page (`<script>` and `"onmouseover=` in every field) | tests | `just server-test` (`WebTests`) | pass |
| No key, token, client secret, address, email, query or body in the log | tests and a smoke run of the built server against a fake GitHub | `just server-test`, `scripts/server_smoke.sh` | pass |
| The API's document lists every `/api/v1` route and the validation's limits | tests that read the real route table | `just server-test` (`OpenApiTests`) | pass |
| NuGet packages are pinned with their hashes; every recipe restores in locked mode | `RestorePackagesWithLockFile` in `app/Directory.Build.props`, a `packages.lock.json` for each of 10 projects, `RestoreLockedMode=true` in the recipes | `just app-test`, `just server-test`, `just pages-test` | fail for one project: `RestoreLockedMode=true dotnet list app/Tests.Fable/Marola.Tests.Fable.fsproj package` stops with NU1004 ("a new project reference to Marola.Client.Core was found"). The other 9 restore. `just app-test` still passes, so it does not catch this [INFERENCE: Fable restores without locked mode]. A person regenerates `app/Tests.Fable/packages.lock.json` |
| No NuGet package has a known vulnerability | `dotnet list package --vulnerable --include-transitive` for each project | `just audit` (by hand, needs network; not in `just quality`) | pass: 0 vulnerable packages in 10 projects, 2026-11-11 (see below) |
| The vendored `MEMBERS.md` is the blob the pin names | a hash compare | `just members-check`, part of `just quality` | pass |
| The design tokens and `style.css` agree; no stray colour | a script with a self-test | `just design-check` | pass |
| The phone nav strip does not scroll sideways | a real browser's layout | `CHROMIUM=... scripts/nav_measure.sh` | unknown: needs a Chromium; not run here, and not part of `just quality` |
| The built site is the same bytes on two runs | `nix build --rebuild` finds no difference ([5-hosting](5-hosting.md#build-with-nix)) | `just nix-build` | unknown: not run in this run. The recorded caveat: `security.txt` holds the build day in `Expires`, so builds on two days differ in that one file. The Nix build does not check the lock files (NU1004 and NU1403 under nixpkgs) |
| The git hook scripts do not touch another repository when git exports `GIT_DIR` | a self-test | `scripts/mip-trailer-check.sh --self-test`, part of `just quality` | pass |
| `AGENTS.md`'s invariants block is the org's | a byte compare with the devkit's block | `agents-check`, part of `just quality` | pass. It checks that block only |
| Docs have no stale wording and no foreign recipe | a linter | `docs-lint`, part of `just quality` | pass |
| NuGet and Actions updates arrive as pull requests | none in the repository | owner step 1 | fail: no `dependabot.yml` ([owner-steps](owner-steps/dependabot.yml)) |
| Static analysis of the F# code | none. CodeQL does not support F#. Its C# analysis reads C# source and the repository has 0 `.cs` files | [owner-steps/codeql.yml](owner-steps/codeql.yml) covers the JavaScript only | fail: nothing analyses `app/` for vulnerabilities except the compiler and the tests. A fuzz test or a penetration test has not been done |
| Actions are pinned by commit SHA | `grep -hn "uses:" .github/workflows/*.yml \| grep -vc '@[0-9a-f]\{40\}'` | `.github/workflows/` | fail: 22 of 22 `uses:` lines use a tag ([pin-actions.md](owner-steps/pin-actions.md)) |
| Private vulnerability reporting, secret scanning, push protection and branch protection are on | repository settings; nothing in the repository reads them | GitHub settings | unknown. An owner reads the settings page ([settings.md](owner-steps/settings.md)) |
| The F# gate runs on every pull request | reading `.github/workflows/ci.yml` | `.github/workflows/ci.yml` | fail: `ci.yml` has no step for `just quality`, `dotnet test` or `just fp-audit`. They run on a developer's machine (`just prepush`). The devkit's `static-ci.yml` was not read |
| A researcher knows how to report a flaw | [SECURITY.md](../SECURITY.md) and `/.well-known/security.txt` | `just pages-test` checks `security.txt`; the policy text is by hand | pass for `security.txt`; unknown for the policy until private reporting is on (above) |

### Vulnerable packages, 2026-11-11

`just audit` ran `dotnet list <project> package --vulnerable --include-transitive --no-restore` against nuget.org
for each of the 10 F# projects (`Shared`, `Client/Core`, `Client/App`, `Pages`, `Pages.Build`, `Pages.Tests`,
`Server`, `Server.Tests`, `Tests`, `Tests.Fable`). The network was reachable. Result: 0 vulnerable packages in
every project, direct and transitive. The advisory database is nuget.org's, as it was that day.
`SQLitePCLRaw.lib.e_sqlite3` is pinned to 2.1.14 on purpose (the comment in `Marola.Server.fsproj`: the default
carries SQLite older than 3.50.2, CVE-2025-6965). The recipe does not restore, so it never rewrites a lock file.

## Agent harness

What lets an agent work here without reading all the code.

| Practice | How checked | Where | Result today |
|---|---|---|---|
| `AGENTS.md` is accurate: every path, recipe and rule it names exists and is true | `agents-check` compares only the invariants block | by hand | unknown. A script that checks that each backticked path exists and each `just` recipe named is in `just --summary` would settle the commands and paths |
| `skill.md` (the API guide for agents) is served and has the endpoint, the dry run, the levels and no key | a test; a smoke run | `just server-test` (`StudyApiTests`), `scripts/server_smoke.sh` | pass |
| Every error code `skill.md` lists has a message in both languages and a place in the OpenAPI enum | tests | `just server-test` (`WebTests`, `OpenApiTests`) | pass |
| The OpenAPI document is served, is 3.1, is cached 300 s, and matches the route table and the validation limits | tests and a smoke run | `just server-test` (`OpenApiTests`), `scripts/server_smoke.sh` | pass |
| `llms.txt` lists the areas, the pages, the API documents and the board contract | tests | `just pages-test` (`MetaTests`) | pass |
| One entry point: the `just` recipes | AGENTS.md lists them; `just --list` | `justfile` | unknown whether every recipe is listed in AGENTS.md. Comparing `just --summary` with the file would settle it |
| Tests are the oracle: one command runs every gate that needs no docker | `just quality` | `justfile` | pass: exit 0, includes the .NET and Fable tests, the smoke self-tests, `agents-check` and `docs-lint` (the full run is below) |
| Hooks run the same gate | the devkit's hooks call `just precommit` and `just prepush`; the dev shell sets `core.hooksPath` | `justfile`, `.devkit/` | unknown for a fresh clone: no check that the hooks are installed. Running `git config core.hooksPath` after `nix develop` in a new clone would settle it |
| A stale generated file fails a check and says how to regenerate | `--check` modes; the table in AGENTS.md ("Never edit by hand") | `just quality` (`golden`, `i18n_bundle`, `news_build`, `members-check`) | pass for `golden`, `i18n_bundle` and `news_build` (`--check` in `just quality`); the members block is checked by `members_build.py --check` in `ci.yml` and by `just members-check` in `just quality`. `nix/deps.json` has no check in `just quality` |
| A generated file says it is generated | the first lines of the file | `site/static/i18n.js`, `site/static/news.html` | pass for these two (`do not edit` in their headers). Not checked for the others |
| The build is hermetic: no network in the build | the Nix sandbox | `just nix-build`, `just package-smoke` | unknown: not run in this run ([5-hosting](5-hosting.md#build-with-nix) records 2026-11-11 runs) |
| The commit rules (`Tested:`, Co-Authored-By, `MIP:` on a legacy change) | a hook and its self-test | `scripts/mip-trailer-check.sh`, `just prepush` | pass for the self-test; the trailers on `Tested:` and Co-Authored-By are by hand |

## Proof of this page

On 2026-11-11, inside `nix develop path:.`:

```
just app-fmt --check && just app-test && just server-test && just pages-test && just app-build --fixtures \
  && scripts/server_smoke.sh && node scripts/client_check.js && just design-check && just fp-audit && just quality
```

exit 0. Test counts: `app/Tests` 181 on .NET and 181 on Node, `Server.Tests` 128, `Pages.Tests` 102.
`client_check`: 131 assertions, 0 failed. `fp-audit`: no count above the baseline.

## Owner steps

Things this branch cannot do, because `.github/` and the repository settings are off limits to it. Each draft is in
[owner-steps/](owner-steps/settings.md); copy it, read it, change it. None of them is applied.

1. **Dependabot.** Copy `docs/owner-steps/dependabot.yml` to `.github/dependabot.yml`. After a NuGet bump a person
   runs `just nix-deps` (it needs the network) so `nix/deps.json` has the new package, and checks the lock file.
2. **Pin the actions.** Apply the 22 replacement lines of [pin-actions.md](owner-steps/pin-actions.md) to
   `.github/workflows/*.yml`. The SHAs are Hermes's of 2026-11-11.
3. **CodeQL.** Copy `docs/owner-steps/codeql.yml` to `.github/workflows/codeql.yml`. It analyses the JavaScript only;
   F# is not supported by CodeQL.
4. **Scorecard.** Copy `docs/owner-steps/scorecard.yml` to `.github/workflows/scorecard.yml`. Decide first whether
   to publish the result.
5. **Run the F# gate in CI.** Add a job that runs `nix develop path:. -c just quality` to `.github/workflows/ci.yml`
   and to the `needs` of `ci-ok`. OPEN: owners. It costs a runner with Nix and the network.
6. **CODEOWNERS.** Copy `docs/owner-steps/CODEOWNERS.draft` to `.github/CODEOWNERS` and write real names for the
   five paths. OPEN: owners.
7. **Repository settings.** Private vulnerability reporting on (SECURITY.md and `security.txt` depend on it), secret
   scanning and push protection on, branch protection on the default branch with `ci-ok` as a required check, no
   force push, reviews. Signed commits are an option with a cost. All in [settings.md](owner-steps/settings.md).
8. **`gemini.yml`.** Read what the devkit's `gemini-review.yml` checks out under `pull_request_target`, and decide
   among the changes in [settings.md](owner-steps/settings.md#5-actions-pull_request_target-in-geminiyml).
9. **`app/Tests.Fable/packages.lock.json`.** Regenerate it with `dotnet restore` in that folder, without
   `RestoreLockedMode` (AGENTS.md), and check the diff: the lock now misses the `Marola.Client.Core` reference.
   Not done here because the same restore also removed `Fable.Core` from the `Marola.Shared` entry, which a person
   should read first.
