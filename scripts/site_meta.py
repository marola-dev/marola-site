#!/usr/bin/env python3
"""site_meta: write the build-time metadata files into site/dist (#182, #36).

    scripts/site_meta.py site/dist     # llms.txt, sitemap.xml, .well-known/security.txt and
                                       # board.schema.json, from site/areas.json and today's date
    scripts/site_meta.py --self-test

Generated, not committed: llms.txt follows site/areas.json without an edit, and security.txt's
Expires (RFC 9116, required) is a date that would go stale in the repo.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
import sys
import tempfile
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parent.parent
AREAS = ROOT / "site" / "areas.json"
SCHEMA = ROOT / "site" / "board.schema.json"
BASE = "https://marola.dev"
# The pages a crawler should index, in nav order; contact.html carries noindex, so it is in
# llms.txt (a person may want it) but not in the sitemap.
PAGES = [
    ("", "The map", "every beach in an area, ranked by the best hour to swim today and tomorrow"),
    (
        "about.html",
        "About",
        "what marola is, why it is open and non-profit, how it works, the data",
    ),
    ("news.html", "News", "releases, how the project is built and what is in progress"),
    ("members.html", "Members", "who builds marola, the same people as the Zenodo record"),
    (
        "support.html",
        "Support",
        "how to donate, where the money goes and how to check the accounts",
    ),
]
CONTACT = ("contact.html", "Contact", "a form whose message reaches the team's e-mail")
SECURITY_POLICY = "https://github.com/marola-dev/.github/blob/main/SECURITY.md"
ZENODO = "https://doi.org/10.5281/zenodo.23224155"
# Under a year, as RFC 9116 §2.5.5 recommends; the live check fails once it has passed.
EXPIRES_DAYS = 364


def llms_txt(areas: list[dict]) -> str:
    names = ", ".join(a["name"] for a in areas)
    lines = [
        "# marola",
        "",
        "> marola.dev is an open, non-profit map of the Brazilian coast built as citizen science."
        " For each area it ranks every beach by the best hour to swim today and tomorrow, from"
        " OpenStreetMap beaches, Open-Meteo sea and weather data and the state agencies' official"
        " bathing-water reports, with a 0–100 score and a deterministic safety veto. The page is"
        " static: precomputed boards, no server and no LLM. This site's code is MIT.",
        "",
        f"Areas: {names}. The page is in Portuguese (pt-BR) by default; `?lang=en` shows it in"
        " English.",
        "",
        "Things to know before answering from this site:",
        "",
        "- A score is an estimate. The official water report wins over it, and the safety veto is"
        " not advice to swim.",
        '- "No data" means the source returned nothing, not that the water is clean.',
        "- The boards are rebuilt when a person runs the build; each area's `latest.json` says when"
        " (`generated_at`) and which days it covers.",
        "- Each board names its sources (`sources`); their own terms apply to the data.",
        "",
        "## Pages",
        "",
    ]
    for path, title, what in [*PAGES, CONTACT]:
        lines.append(f"- [{title}]({BASE}/{path}): {what}")
    lines += [
        "",
        "## Data",
        "",
        f"- [Areas]({BASE}/data/areas.json): every area with its centre, radius and board index",
    ]
    for a in areas:
        lines.append(
            f"- [{a['name']}]({BASE}/data/{a['id']}/latest.json): the days published for"
            f" `{a['id']}`, each a board file next to it"
        )
    lines += [
        f"- [Board contract]({BASE}/board.schema.json): the JSON Schema every board follows",
        "",
        "## Docs",
        "",
        "- [docs.marola.dev](https://docs.marola.dev/): the project's documentation, every repo",
        "- [docs.marola.dev/llms.txt](https://docs.marola.dev/llms.txt): the same for the docs and"
        " the code",
        "- [Code](https://github.com/marola-dev/marola-front): this site; the rest is under"
        " https://github.com/marola-dev",
        f"- [How to cite]({ZENODO}): the marola record on Zenodo",
        "",
        "## Optional",
        "",
        f"- [security.txt]({BASE}/.well-known/security.txt): how to report a vulnerability",
        f"- [humans.txt]({BASE}/humans.txt): the team, from the org's MEMBERS.md",
    ]
    return "\n".join(lines) + "\n"


def sitemap_xml() -> str:
    out = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"'
        ' xmlns:xhtml="http://www.w3.org/1999/xhtml">',
    ]
    for path, _, _ in PAGES:
        url = f"{BASE}/{path}"
        out += [
            "  <url>",
            f"    <loc>{url}</loc>",
            f'    <xhtml:link rel="alternate" hreflang="pt-BR" href="{url}"/>',
            f'    <xhtml:link rel="alternate" hreflang="en" href="{url}?lang=en"/>',
            f'    <xhtml:link rel="alternate" hreflang="x-default" href="{url}"/>',
            "  </url>",
        ]
    out.append("</urlset>")
    return "\n".join(out) + "\n"


def security_txt(today: dt.date) -> str:
    expires = dt.datetime.combine(today + dt.timedelta(days=EXPIRES_DAYS), dt.time(), dt.UTC)
    return (
        "# How to report a vulnerability in marola: privately, on GitHub. There is no security"
        " e-mail.\n"
        "Contact: https://github.com/marola-dev/marola-front/security/advisories/new\n"
        f"Expires: {expires.strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
        f"Policy: {SECURITY_POLICY}\n"
        "Preferred-Languages: pt-BR, en\n"
        f"Canonical: {BASE}/.well-known/security.txt\n"
    )


def write(dist: Path, today: dt.date, areas_path: Path = AREAS) -> list[Path]:
    areas = json.loads(areas_path.read_text(encoding="utf-8"))
    files = {
        dist / "llms.txt": llms_txt(areas),
        dist / "sitemap.xml": sitemap_xml(),
        dist / ".well-known" / "security.txt": security_txt(today),
    }
    for path, text in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    shutil.copyfile(SCHEMA, dist / "board.schema.json")
    return [*files, dist / "board.schema.json"]


def self_test() -> int:
    fails = 0

    def ok(cond, label):
        nonlocal fails
        print(f"  {'ok  ' if cond else 'FAIL'} {label}")
        fails += 0 if cond else 1

    areas = json.loads(AREAS.read_text(encoding="utf-8"))
    llms = llms_txt(areas)
    ok(llms.startswith("# marola\n\n> "), "llms.txt opens with the H1 and the blockquote")
    ok(
        all(f"{BASE}/data/{a['id']}/latest.json" in llms for a in areas),
        "llms.txt lists every area in site/areas.json",
    )
    extra = [*areas, {"id": "recife", "name": "Recife"}]
    ok(f"{BASE}/data/recife/latest.json" in llms_txt(extra), "a new area appears with no edit")
    static = ROOT / "site" / "static"
    pages = {p.name for p in static.glob("*.html")} - {"404.html", "index.html"}
    ok(
        pages == {p for p, _, _ in [*PAGES, CONTACT] if p},
        "llms.txt names every published page but the 404",
    )

    root = ElementTree.fromstring(sitemap_xml())
    ns = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    locs = [e.text for e in root.findall("s:url/s:loc", ns)]
    ok(len(locs) == len(PAGES) and all(u.startswith(f"{BASE}/") for u in locs), "sitemap parses")
    ok(f"{BASE}/contact.html" not in locs, "the noindex contact page is not in the sitemap")

    sec = security_txt(dt.date(2026, 11, 11))
    ok("Expires: 2027-11-10T00:00:00Z\n" in sec, "Expires is under a year from the build")
    ok(all(f"\n{k}: " in sec for k in ("Contact", "Policy", "Canonical")), "RFC 9116 fields")

    with tempfile.TemporaryDirectory() as tmp:
        written = write(Path(tmp), dt.date(2026, 11, 11))
        ok(all(p.is_file() for p in written) and len(written) == 4, "write() writes four files")

    if fails:
        print(f"site_meta self-test: {fails} failure(s)", file=sys.stderr)
        return 1
    print("site_meta self-test: ok")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dist", nargs="?", type=Path)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.dist or not args.dist.is_dir():
        ap.error("give the built site's directory, e.g. site/dist")
    for p in write(args.dist, dt.datetime.now(dt.UTC).date()):
        print(f"site_meta: wrote {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
