#!/usr/bin/env python3
"""Turn the Archify HTML pages in .tmp/figures/ into the site's static figure pages.

The generated page is an interactive HTML/SVG document with inline scripts and styles. The site
serves no inline script or style (its CSP), so this keeps the drawing and drops the interaction:
the toolbar and its scripts go, the styles move to site/figures/archify.css, and each page gets a
small header, a canonical URL and a title. `just figures` runs Archify first; this script is the
part that makes the output servable.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "docs" / "archify"
TMP = ROOT / ".tmp" / "figures"
OUT = ROOT / "site" / "figures"

HEADER = (
    '<header class="archify-head">'
    '<a href="/">marola</a> <span aria-hidden="true">·</span> '
    '<a href="/about.html">about</a>'
    "</header>"
)

HEADER_CSS = """
.archify-head{position:fixed;top:12px;left:16px;z-index:10;font:500 12px/1.2 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.04em}
.archify-head a{color:#9AA3B2;text-decoration:none}
.archify-head a:hover{color:#EDEFF3}
.toolbar,.diagram-nav,.focus-chip,.archify-toast{display:none!important}
"""


def styles(html: str) -> tuple[str, str]:
    found = re.findall(r"<style\b[^>]*>(.*?)</style>", html, flags=re.S)
    return "\n".join(found), re.sub(r"<style\b[^>]*>.*?</style>", "", html, flags=re.S)


def scripts(html: str) -> str:
    return re.sub(r"<script\b[^>]*>.*?</script>", "", html, flags=re.S)


def toolbar(html: str) -> str:
    html = re.sub(r'<div class="toolbar".*?(?=<!-- Main Diagram -->)', "", html, flags=re.S)
    return re.sub(
        r'<div class="toolbar".*?(?=<div class="diagram-container")', "", html, flags=re.S
    )


def clean_css(css: str) -> str:
    css = re.sub(r"@font-face\s*\{[^}]*\}", "", css, flags=re.S)
    css = re.sub(r"@import\s+url\([^)]*https?[^)]*\)[^;]*;", "", css, flags=re.S)
    css = re.sub(r"[ \t]+\n", "\n", css)
    return re.sub(r"[ \t]+\n", "\n", css + HEADER_CSS)


def page(slug: str, source: dict[str, object], html: str) -> str:
    title = str(source.get("meta", {}).get("title", slug))  # type: ignore[union-attr]
    html = scripts(toolbar(html))
    html = re.sub(r"<title>.*?</title>", f"<title>{title} — marola</title>", html, flags=re.S)
    head = (
        f'<link rel="canonical" href="https://marola.dev/{slug}">\n'
        f'<meta name="description" content="{title}">\n'
        '<link rel="stylesheet" href="/archify.css">\n'
    )
    html = html.replace("</head>", head + "</head>", 1)
    return re.sub(r"[ \t]+\n", "\n", html.replace("<body>", "<body>\n" + HEADER, 1))


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    css = None
    for src in sorted(SOURCES.glob("*.json")):
        slug = src.stem
        generated = TMP / f"{slug}.html"
        if not generated.is_file():
            raise SystemExit(f"archify_figures: no {generated}; run `just figures`")
        source = json.loads(src.read_text(encoding="utf-8"))
        html = generated.read_text(encoding="utf-8")
        page_css, html = styles(html)
        if css is None:
            css = clean_css(page_css)
        (OUT / f"{slug}.html").write_text(page(slug, source, html), encoding="utf-8")
        print(f"archify_figures: {slug}.html")
    if css is None:
        raise SystemExit("archify_figures: no Archify source in docs/archify/")
    (OUT / "archify.css").write_text(css, encoding="utf-8")
    print(f"archify_figures: archify.css ({len(css)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
