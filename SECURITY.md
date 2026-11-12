# Security policy

## Report a vulnerability

Report it privately, on GitHub, for this repository:
<https://github.com/marola-dev/marola-front/security/advisories/new>

This is the same address as `/.well-known/security.txt`. There is no security e-mail address. Do not open a public
issue or a pull request for a vulnerability. Write in Portuguese or English.

Say what you did, what you saw, and what you expected. A request and its answer (with any key or cookie removed)
helps most. Do not send a real person's data: use your own test account.

## In scope

- The server in `app/Server`: routes, headers (`Security.fs`), sessions, CSRF, rate limits, the contact form.
- The pages in `app/Pages` and the pages of the server (`Views.fs`), including escaping of study text.
- The study submission and the PDF intake: the upload, the name scan, the store, the PDF route.
- The API under `/api/v1`, including the API keys.
- The Nix package in `nix/`, as far as it changes what the server runs.

## Out of scope

- The legacy page in `site/static/` is plain JavaScript and has no server of its own. A flaw in a vendored library
  goes to that library; tell us too if marola ships the affected version.
- The host, its nginx, its backups and the Cloudflare account: a person runs them, not this repository.
- Mapbox, OpenFreeMap, GitHub, Cloudflare and other services. Report to them.
- Denial of service by volume, social engineering, and physical access.
- A wrong claim in a study. Studies are labelled "not reviewed"; use the report form or the takedown page.
- Findings from a scanner with no working proof.

## What to expect

We aim to acknowledge a report within 7 days. This is a target, not a promise: the team is volunteers. We then
say whether we can reproduce it, work on a fix in private, and credit you in the advisory if you want that.

## Supported version

The branch that serves marola.dev: the default branch of this repository. Older commits and other branches
get no fixes.

## Safe harbor

If you act in good faith, test only with your own account, read no more data than you need to show the problem,
do not harm other people or the service, and report to us before you tell anyone else, we will not take legal
action against you for that research and we will say so to anyone who asks.

## Known limits

These are known and written down; a report of one of them is welcome but is not a surprise.

- Studies are public at once and not reviewed. The board hides a study after the fact. See the threat table in
  [ADR 0004](docs/adr/0004-study-submission.md).
- The PDF scan reads names in the file and in compressed object streams. It does not scan plain streams, and a
  bug in a PDF viewer is not covered.
- The per-key rate limiter is in memory: a restart resets it.
- A person with many old GitHub accounts can post within the limits of each account.
- The legal text of the privacy page is the project's own description of its practice. The board has not approved
  it and a lawyer has not reviewed it.
- The measured state of the checks is in [docs/7-quality.md](docs/7-quality.md), with what is not measured.
