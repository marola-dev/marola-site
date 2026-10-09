# Blog posts

The posts on [marola.dev/blog.html](https://marola.dev/blog.html): longer pieces on why marola is
built the way it is. They follow the news format ([`../news/README.md`](../news/README.md)), one
Markdown file per post and language, plus a `tags:` line right after the date:

```markdown
# <title>

YYYY-MM-DD

tags: adr

<the lede>
```

Every tag is declared once in [`tags.json`](tags.json), with its name and what it means in pt-BR
and en; the build fails on an undeclared tag or a post whose two languages carry different tags.
`scripts/posts_build.py` writes the posts and the index at the top of `blog.html` (the posts,
newest first, then each tag in use with what it means); edit the posts here, never the generated
blocks.

| Tag | For |
|---|---|
| `adr` | an architecture decision record: the context, the decision, why, and its consequences |

## Index

| Date | Post | Tags | For |
|---|---|---|---|
| 2026-10-09 | [The Lake](2026-10-09-o-lago.en.md) ([pt-BR](2026-10-09-o-lago.pt-BR.md)) | `adr` | #102 |
