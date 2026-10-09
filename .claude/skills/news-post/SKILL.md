---
name: news-post
description: Use when writing, editing or reviewing a news post on marola.dev (site/content/news/*.md, news.html), or when asked about a post's reading time, so each post ships in pt-BR and en with its sources linked and an up-to-date reading time
---

# news-post: a post on marola.dev/news.html

## Where a post lives

One Markdown file per post and language in `site/content/news/`:
`YYYY-MM-DD-<slug>.pt-BR.md` and `YYYY-MM-DD-<slug>.en.md`, both required. The format and the index
of posts are in `site/content/news/README.md`. `scripts/news_build.py` renders the posts into the
marked block of `site/static/news.html`; nobody edits that block by hand.

## Reading time

Every post shows its reading time next to the date ("5 min de leitura", "4 min read"), so a reader
knows what the post asks of them before starting. **It is computed, never written:**
`news_build.py` counts the words of the title and body (not link targets, not markup) and divides
by `WORDS_PER_MINUTE` (200, a silent-reading rate for non-fiction), rounding up, at least 1. Each
language gets its own figure.

To update it after any edit, run the build; `--check` in CI fails while the page shows a stale
time. Do not add a reading-time line to the Markdown, and do not change `WORDS_PER_MINUTE` to make
a post look shorter: cut the post instead.

## Writing or changing a post

1. Write the pt-BR file first (site lowercase house style, `ptbr-humanizer`), then the en file
   (`humanizer`). Same sections, same facts, same links in both.
2. Every claim links to what backs it: a repo file, a PR, an issue, a DOI (`citizen-science-site`).
   State work in progress as in progress; never present a plan as done.
3. Add the post's row to the index in `site/content/news/README.md`.
4. `python3 scripts/news_build.py`, then `python3 scripts/news_build.py --check` and
   `node scripts/site_check.js`.
5. Screenshots of `news.html` at 1280 × 800 and 390 × 844, both languages, in the PR body
   (AGENTS.md, "Screenshots in the PR").
6. The commit touches `site/static/news.html`, so it carries a `MIP:` trailer (MIP-0044 for posts).

## Checking an existing post

- Reading time on the page matches the build: `python3 scripts/news_build.py --check`.
- pt-BR and en say the same thing; a fact changed in one changed in the other.
- Links still resolve, and "in review" or "no data yet" statements are still true; a post that
  went stale gets a dated update paragraph at its end, not a silent rewrite.
