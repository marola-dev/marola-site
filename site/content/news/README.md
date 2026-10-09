# News posts

The posts on [marola.dev/news.html](https://marola.dev/news.html), one Markdown file per post and
language: `YYYY-MM-DD-<slug>.pt-BR.md` and `YYYY-MM-DD-<slug>.en.md`, both required.
`scripts/news_build.py` writes them into `site/static/news.html`, newest first; edit the posts here,
never the generated block in `news.html`. `just quality` and CI run `news_build.py --check`, which
fails on a stale page or a post that breaks the format below.

```markdown
# <title>

YYYY-MM-DD

<the lede: one paragraph, shown larger>

## <section>

<paragraphs, `- ` lists, ### subsections>
```

The date line repeats the file's date. Inside a post: `##` and `###` headings, paragraphs, `- `
lists, `[text](url)`, `**bold**` and `` `code` ``; anything else fails the build. The reading time
next to the date is computed by the build (the `news-post` skill has the rule); never write it.
Portuguese follows the site's lowercase house style and the `ptbr-humanizer` skill; every claim
links to what backs it (`citizen-science-site`).

## Index

| Date | Post | For |
|---|---|---|
| 2026-10-09 | [marola is out](2026-10-09-marola-is-out.en.md) ([pt-BR](2026-10-09-marola-is-out.pt-BR.md)) | #7, #96 |
