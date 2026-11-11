# ADR-0004: Study submission

| | |
|---|---|
| **Status** | Proposed |
| **Date** | 2026-11-11 |

## Context

Scientists should be able to publish a study on marola, as they do on aiXiv. The owner's rule: anyone with a
GitHub account may submit, nobody approves first, and the board may hide a study afterwards. A wrong
water-quality claim can harm people, so every public view says "not reviewed, not medical advice" and keeps
the hash and the date of the study. Agents submit over an HTTP API that has a dry-run mode. This ADR covers
the domain, the storage, the validation and the API (run C3a). Run C3b adds the GitHub login, the sessions, the
web pages, the reports and the withdrawal. The privacy text and the board's takedown command are not built yet.

## Decision

1. **Code.** `app/Shared/Study.fs` has the record types, the field validation with machine codes, the ORCID
   check, the enums and the JSON text of the answers (a small writer, so the server needs no JSON package).
   It compiles with .NET and Fable, and `app/Tests/StudyTests.fs` runs on both. `app/Server` has
   `StudyStore.fs` (SQLite), `PdfIntake.fs` (the file), `StudyApi.fs` (the routes) and `DevAccount.fs`.
2. **Fields.**

   | Field | Rule |
   |---|---|
   | `title` | 5 to 200 characters, one line |
   | `authors` | 1 to 20 lines, `Name` or `Name \| ORCID`; a name has 2 to 120 characters; the ORCID needs the `\d{4}-\d{4}-\d{4}-\d{3}[\dX]` shape and the ISO 7064 MOD 11-2 check character |
   | `abstract` | 100 to 4000 characters |
   | `area` | `rio`, `floripa`, `salvador`, `other` |
   | `topic` | `water-quality`, `waves`, `wind`, `trails`, `ecology`, `safety`, `data`, `other` |
   | `sources` | 0 to 10 https links, each accepted by `Html.safeHref` |
   | `repository` | optional https link |
   | `licence` | `CC-BY-4.0` (default), `CC-BY-SA-4.0`, `CC0-1.0`. Open licences only, because marola hosts the file |
   | `rights` | must be `true`: the author may publish this file under that licence |
   | `ai_models` | 0 to 300 characters |
   | `ai_contribution` | one of six levels, below |
   | `ai_process` | 0 to 1500 characters; required unless the level is `none` |
   | `pdf` | the file |

   Authors and sources are one field each with one entry per line, because a repeated field name is refused.
   The levels, from the least to the most AI work: `none` (no AI took part), `language-editing` (fixed or
   translated text; the ideas and results are the authors'), `analysis-assistance` (code, data or statistics
   help; the authors checked it), `drafting` (an AI wrote parts; the authors planned, edited and checked),
   `substantial` (an AI did most of the analysis or writing; the authors directed and checked),
   `autonomous` (no human step between the question and the file). The author states the level; marola does
   not verify it. Text fields drop control characters except newline and tab, and the length counts
   UTF-16 code units after that.
3. **The PDF.** At most 20 MB. It must start with `%PDF-` at byte 0, and `startxref` and `%%EOF` must lie
   in the last 1024 bytes. The active-content rule, exactly: read every byte for PDF names (a `/` and the
   regular characters after it, with `#xx` escapes decoded, so `/J#53` is `/JS`). Refuse the file when a name is
   `/Launch`, `/JavaScript`, `/JS` or `/EmbeddedFile`, anywhere, in a stream too. Refuse `/OpenAction` when its
   value is not a destination array (`[`), an indirect reference (a digit) or `null`; so `/OpenAction << ... >>`
   is refused and `/OpenAction [3 0 R /Fit]` (what hyperref writes) is not. Tests: each name, the escaped forms,
   a name that straddles the 64 KB read border, and the accepted forms. The file is streamed in 64 KB chunks to
   `MAROLA_STUDIES/.incoming/<random>` (mode 0640) while SHA-256 is computed, then moved to `<sha256>.pdf`. The
   path is built from a hash that passed a 64 lower-case hex check, never from user text. The size limit applies
   while reading, so an endless body stops at 20 MB. A dry run does the same checks and creates no file.
4. **Store and quota.** `MAROLA_STUDIES_QUOTA` (2 GiB) bounds the sum of the stored files. A new file over it gets
   507, a dry run too. A file that is already stored costs nothing: the same bytes from two accounts are one file.
   The same hash from the same account is a 409 with the old id (a unique index on account and hash decides a race).
5. **Database.** The SQLite file of the contact form. `PRAGMA user_version` is the schema version; `StudyStore.migrate`
   applies each missing step in a transaction at start. Version 1 adds `accounts`, `api_keys`, `studies`, `reports`.
   No email address is stored. A `reports` row has the study, the date, the reason and an optional GitHub id of the
   reporter; C3b fills it. Foreign keys are on.
6. **Accounts and keys.** C3b's login calls `upsertAccount` with the GitHub id, the login and the GitHub
   `created_at`. A key is `msk_` and 52 lower-case base32 characters (32 random bytes). Only its SHA-256 is stored, the
   key is shown once, an account has at most 3 active keys, and a key can be revoked. The lookup is by hash and
   the stored hash is compared with `CryptographicOperations.FixedTimeEquals`; an attacker cannot pick a
   hash prefix without a preimage, so the lookup does not leak the key.
7. **API.** `POST /api/v1/studies` (multipart, `Authorization: Bearer`, `?dry_run=1`), `GET /api/v1/studies`
   (`area`, `topic`, `before`, `limit` up to 50; public studies only), `GET /api/v1/studies/<id>`,
   `GET /api/v1/skill.md`, `GET /studies/<id>.pdf`. The order of the checks is: key (401), account age (403,
   the code `account_too_new`), key rate (429), media type (415), gap and daily limit (429), then the body:
   all field errors at once (400), the file (400, or 413 for a size), duplicate (409), quota (507), and the
   store. The id is 10 random base32 characters. `url` in the answer is the page of C3b; the JSON record is at
   `/api/v1/studies/<id>`. A hidden study answers with a tombstone (id, hash, date, status, reason; no text, no
   link) and its file is never served; the file stays on disk.
8. **Limits.** One real submission per account every 10 minutes and 10 a day (counted from the table, so they
   survive a restart), 30 requests a minute per key (90 units: a real submission costs 3, a dry run 1; in
   memory), the account must be 7 days old on GitHub. A dry run is subject to the same refusals as a real one
   and stores nothing, so it does not use up the 10 minutes. The upload route has a body limit of 21 MB on its
   own; every other route keeps 1 MB.
9. **Multipart.** Parsed as a stream with `MultipartReader`: at most 20 parts, 8 headers of 4 KB each, 20,000 bytes
   for a text field, a boundary of at most 70 characters. A repeated name, an unknown name and bytes that are not
   UTF-8 are errors; a truncated body is a 400.
10. **Output.** JSON is `application/json; charset=utf-8` with `nosniff`, escapes `<`, `>` and `&`, and holds no
    stack trace. The PDF route sends `application/pdf`, `Content-Disposition: inline; filename="<id>.pdf"` (the
    id passed the base32 check), `nosniff`, `Content-Security-Policy: sandbox; default-src 'none'` (it
    replaces the page policy: `Security.fs` sets the page CSP only when the route did not set one) and
    `Cache-Control: public, max-age=3600`.
11. **Logs.** The study id and the account id. No address, title, abstract, file name or key.
12. **`dev-account`.** `marola-server dev-account --login <name> --age-days <n>` makes an account and prints a key,
    for `scripts/server_smoke.sh`. It refuses unless `MAROLA_DEV=1`.
13. **GitHub login.** The web flow with an empty scope: the app reads only the public profile (id, login,
    `created_at`). `GET /auth/github/login` puts a random `state` in the cookie `__Host-mstate` (HttpOnly, Secure,
    SameSite=Lax, Path=/, 10 minutes) and redirects to GitHub. `GET /auth/github/callback` compares `state` in
    constant time, exchanges the code on the server over HTTPS, reads `/user`, drops the GitHub token at once
    (it is a local variable, never stored and never logged), upserts the account and starts a session. A failure
    shows a plain page with no text from GitHub and no stack trace. The login page language rides in the state
    cookie (`<state>.en`), so the callback returns to `/en/account`. The client id is `MAROLA_GITHUB_CLIENT_ID`; the
    secret is read from the file `MAROLA_GITHUB_CLIENT_SECRET_FILE`, never from the environment (it fits
    systemd `LoadCredential`). Without both, login answers 503 and the rest of the site works.
    `MAROLA_GITHUB_BASE` and `MAROLA_GITHUB_API_BASE` count only when `MAROLA_DEV=1`, so a test or the smoke script
    can use `scripts/fake_github.mjs`; in production the code and the secret can go only to github.com.
14. **Sessions and CSRF.** A session is 32 random bytes in the cookie `__Host-msess` (HttpOnly, Secure, SameSite=Lax,
    Path=/). Only its SHA-256 is stored (table `sessions`, schema version 2). It lasts 12 hours from login, absolute;
    using it does not extend it. Logout is a POST that deletes the row. `MAROLA_DEV=1` drops `Secure` and the
    `__Host-` prefix, which plain HTTP on 127.0.0.1 cannot carry; the smoke script and the tests use it. Every POST
    that changes an account checks the Origin against the Host (the code of the contact form) and a hidden field
    `csrf`: the HMAC-SHA256 of the session's hash, with a key made at the first start in `csrf.key` next to the
    database (mode 0600). A POST without the token is 403. In the multipart form the token is the first field, and
    the file part is not read when it is missing or wrong, so a post with no token stores nothing. The login GET
    looks state-changing and is safe by `state`.
15. **One intake.** `StudyApi.intake` does everything after the caller is known (account age, limits, multipart,
    fields, file, duplicate, quota, insert). The API calls it with a key, the web form with a session. It returns
    an outcome; the API writes JSON and the web writes a page. `Messages.fs` has the text of every error code in
    both languages; a test fails when a code the API can send has no text in a language. The form shows every
    error at once, next to its field, and keeps what the author typed.
16. **Pages.** `Views.fs` and `Web.fs` in `app/Server` use `Layout.page` of `app/Pages`, so the head, nav and
    footer match the static pages, in pt-BR at the root and in English under `/en/`. They carry no script and
    no inline style. `Layout` has a `Dynamic` flag for an address with no `.html`. Routes: `/submit`, `/studies`
    (area, topic, `before`, 20 a page), `/studies/<id>`, `/studies/<id>.pdf`, `/studies.atom` (the 50 newest, valid
    Atom), `/account` (keys, studies, withdraw, logout), `/report/<id>`. Study text goes through the Vdom, which
    escapes it; a test puts `<script>` and `"onmouseover=` in every field. A tombstone has no text and no file
    and carries `noindex`; so do the account and report pages. Everything is `no-store`, except the list and the
    study pages (`max-age=60`) and the PDFs. The nav has "Estudos" and "Studies", and the footer has "Enviar" and
    "Submit". On a phone the nav link is hidden, as the others are, and `about` links it.
17. **Reports.** `/report/<id>` takes a reason from a short list and free text of up to 1000 characters. It needs no
    login and has no email field. A `reports` row has the study, the time and the reason, and no address and no
    account. The strict limiter of the contact form (10 in 10 minutes per client) covers it and keeps counters
    only. A hidden field is a honeypot: a bot gets the thank-you page and nothing is stored.
18. **Withdraw.** The author hides their own study from the account page: status `hidden`, reason "withdrawn by
    the author". Another account's study is never touched.
19. **What is stored.** The GitHub id, the login and the date the GitHub account was made; a session hash; a key
    hash. No email and no IP address. The study pages are not in the static `sitemap.xml`, because they change at
    run time; the sitemap lists `/submit` and `/studies` in both languages, and the Atom feed lists the studies.

## Packages

None added. Everything uses the shared framework (`MultipartReader`, `TimeProvider`, `Microsoft.Data.Sqlite`,
`HttpClient`, `System.Text.Json`, HMAC). `app/Server` now references `Marola.Pages`, which has the page layout and
the catalog loader; `Thoth.Json.Newtonsoft` comes with it and was already a package of the repository. The two
`packages.lock.json` files of the server projects were regenerated for that.

## Threats

| Threat | What we do | What is left |
|---|---|---|
| Malicious PDF (script, launch, attachment) | Magic and tail checks, the name scan of decision 3, a sandbox CSP and `nosniff` on the one route that serves it, no path from user text | The scan reads raw bytes. An action inside a compressed object stream (`/ObjStm`) is not seen, and `/ObjStm` cannot be refused because most LaTeX output has it. A random compressed stream can contain `/JS` followed by a delimiter by chance (about 7 in 100 for a 20 MB file of random bytes, 0.3 in 100 for 1 MB), so a rare file is refused wrongly; the author exports it again. A viewer bug is not covered. Serving `inline` was the owner's decision |
| Spam, mass posting | GitHub account of 7 days, 1 per 10 minutes, 10 a day, 30 requests a minute per key, 3 keys, the general limit per address | A person with many old accounts. The board hides after the fact |
| Abuse (false claims, hate, doxxing) | The label "not reviewed, not medical advice", the hash and the date in every view, the tombstone, the report form, the withdrawal by the author | The harm between the post and the hiding. The board's takedown command is not built yet |
| Enumeration and scraping | Random 10-character ids (50 bits), `limit` of 50 | The list is public on purpose, so every public study can be read |
| Key theft | Only the hash is stored, shown once, 3 keys, revoke, constant-time compare, no key in a log or a header | A stolen key posts until it is revoked, within the limits above |
| Storage exhaustion | 20 MB a file, 21 MB a request, 2 GiB quota with 507, streaming to disk, one file per hash, 1 per 10 minutes, temp files removed on every error | A full disk from other causes. Watch the folder |
| LGPD | No email stored, no IP address stored, nothing from GitHub but the id, the login and the account date. The record holds the GitHub login and id of the author, which the author published on GitHub, and the names and ORCID iDs that the author typed. The server logs no address | The names are personal data of the authors listed, who may not be the submitter. The privacy text, the takedown route and the deletion of a record on request are still to do. The file and its hash stay on disk after hiding until a deletion order |
| Cross-site request forgery | `SameSite=Lax` cookies, the Origin check, a token bound to the session in every POST form, `form-action 'self'` | A browser that sends no Origin and no Referer on a POST is refused |
| Session theft | HttpOnly, Secure, `__Host-` cookies, only a hash stored, 12 hours, no script on any page | A person with the cookie is the account until it ends or they log out |

## Consequences

- `PRAGMA user_version` is now the schema version of `marola.db`. A step is never edited, only appended.
- Hiding a study by the board is a database change (`StudyStore.hide`). The author can withdraw their own study on the account page.
- nginx needs the upload location of [the hosting page](../5-hosting.md).
- The per-key rate is in memory and resets on a restart.
- `url` of a receipt is the study page of decision 16.
- The owner registers the GitHub OAuth app (see [the hosting page](../5-hosting.md#the-github-login)); until then login answers 503.
- Disk for `MAROLA_STUDIES_QUOTA` and a backup of the folder with the database are now part of the host plan.
