# ADR-0003: The static pages in F#

| | |
|---|---|
| **Status** | Superseded in part by [ADR-0005](0005-elm-and-haskell.md) (2026-11-12): the renderer is Haskell (`back/pages`), not F#. Pages from Markdown at build time, with no script, stand |
| **Date** | 2026-11-11 |

## Context

The new map page links to about, support, news, members, contact and a 404. Those pages exist only
as hand-written files in `site/static/`, which carry both languages in one file and need `ui.js` and
`i18n.js` to switch. The server of [ADR 0002](0002-dotnet-server.md) serves static files and a
form route; it has no page of its own.

## Decision

1. Render each page ahead of time from F#, in `app/Pages` (.NET only). One page is a function from
   a language to its HTML text. `Vdom.toHtml` in the client core turns a node tree into text, so
   the pages use the same node type as the map page. It escapes text and attribute values, has no raw
   node, and so no message can add markup.
2. Write pt-BR at the root and English under `/en/`: `about.html` and `en/about.html`. The file path
   is the language. Each file has its own `<html lang>`, a canonical link, `hreflang` alternates and a
   language switch made of two plain links. No `?lang=` and no script are needed.
3. Keep the prose in `site/content/pages/<page>.<lang>.md`, one small Markdown subset
   (`app/Pages/Markdown.fs`). A page's words are edited there, and the words of the chrome stay in
   the catalogs of `site/i18n/`. Markdown that the subset does not know is an error, as in
   `scripts/news_build.py`.
4. Build with a console project, `app/Pages.Build`, and not a subcommand of the server. The
   server stays free of build code and of the catalog reader, and the build has no port. The
   F# era's `pages-build` recipe and `scripts/app_build.sh` ran it (both removed by ADR 0005).
5. The pages use `app/Client/public/style.css` and the favicon, and carry no script, no `<style>` and
   no `style=` attribute. The CSP does not change.
6. The contact form posts to `/contact` (pt-BR) or `/en/contact` (English). The server answers 303
   to `/contact-sent.html` or `/en/contact-sent.html`, a static page. A separate page works with no
   script and no CSS trick, can be linked and tested, and keeps the language of the form. A
   CSS `:target` message would need the same server change (a fragment in `Location`) and would not
   show on a reload.
7. A path that matches no file gets `404.html`, or `en/404.html` below `/en/`, with status 404. The
   404 page has no canonical link: it answers any address.

## Consequences

- The pages were checked by the F# era's `pages-test` recipe (removed by ADR 0005; `just back-test` now): language, canonical, alternates, favicon, no script,
  no style, the form, the credits of the about page, and a file for every nav link.
- The Markdown carries two forms beyond the news subset: `::lede`, `> ` quotes, figures, and
  `{{soon name|label}}` for a channel that is not open yet.
- `news` and `members` are built from data, not from prose: `site/content/pages/<page>.<lang>.md` holds only
  their `title:` and `description:`. `app/Pages/News.fs` reads `site/content/news/` with the rules of
  `scripts/news_build.py` (a post in both languages, the date line, release cards, the README index,
  the reading time rounded up). `app/Pages/Members.fs` reads MEMBERS.md with the rules of
  `scripts/members_build.py`; a wrong row or header fails the build. Each language page shows only its own
  posts, newest first. A bare `about.html` link in a post stays: it resolves to the page of the same language.
- MEMBERS.md is not in this repo. `app/Pages.Build` fetches it at the commit of `site/members.version`
  from raw.githubusercontent.com, or reads the file in `MEMBERS_SOURCE` when the build has no network.
  The avatars in `site/static/img/members/` are copied into `app/dist/img/members/`; the page never asks
  GitHub for an image. The tests rebuild a table from the old members page, as the repo has no copy.
- `app/Pages/Meta.fs` writes `robots.txt`, `sitemap.xml`, `llms.txt`, `humans.txt` and
  `.well-known/security.txt` (`Expires` 364 days after the build) with the rules of `scripts/site_meta.py`.
  The sitemap lists every page in both languages with its alternates, and no `noindex` page. The server
  allows one hidden name, a first segment `.well-known`; every other dot path stays 404.
- The Python builders and the old `site/static` files stay until the cutover. `EqualityTests` builds the
  pages from the real content and compares them with the old `news.html`, `members.html`, `humans.txt`
  and `robots.txt`: the same posts, people and words, in the same order.
- The old `404.html` forwarded `/docs/*` to `docs.marola.dev` with a script. The new page has no
  script, so that forward must move to nginx before the cutover.
- The prose of about and privacy still names Mapbox, as the old pages did. It changes with the
  switch to MapLibre, in the Markdown.
- The support page had an empty `<code class="addr">` for a blockchain address. It is not rendered.
  When there is an address, add it to `support.<lang>.md` as a link.
