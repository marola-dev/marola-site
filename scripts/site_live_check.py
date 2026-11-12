#!/usr/bin/env python3
"""Check what marola.dev actually serves, not what the build believed it wrote.

Two silent failures got past everything else and were both found by a human looking at the page:
docs/ sat on the site-data branch for hours while /docs 404'd, and every Florianópolis beach read
"no data" while the board still named IMA/SC as its source. Both builds were green.

The gap is that every existing gate checks inputs — fixtures, schemas, a stub DOM. Nothing looked
at the published result. This does, and it is deliberately about the *data being present*, not
about HTTP 200s.

    scripts/site_live_check.py                     # check https://marola.dev
    scripts/site_live_check.py --base http://localhost:8000
    scripts/site_live_check.py --self-test

It also reads the crawl files (#182, #36): robots.txt names the sitemap, every sitemap <loc> and
every llms.txt link answers 200, and security.txt has a Contact and an Expires still ahead.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import urllib.error
import urllib.request
from xml.etree import ElementTree

DEFAULT_BASE = "https://marola.dev"
SCHEMA = 1
# A beach that must exist and must carry water data, per area with a provider. Named rather than
# "any beach", so a board that silently shrinks to two beaches still fails.
CANARIES = {"floripa": "Praia do Campeche"}


def fetch(url: str, timeout: int = 30):
    with urllib.request.urlopen(url, timeout=timeout) as r:  # noqa: S310 - fixed https base
        return json.loads(r.read().decode("utf-8"))


def fetch_text(url: str, timeout: int = 30) -> tuple[int, str]:
    """(status, body); an HTTP error is a status, not an exception."""
    req = urllib.request.Request(url, headers={"User-Agent": "marola-front_live_check"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:  # noqa: S310 - fixed https base
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""


LINK = re.compile(r"\]\((https?://[^)\s]+)\)")
SITEMAP_NS = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}


def check_meta(base: str, text=fetch_text, now: dt.datetime | None = None) -> list[str]:
    """robots.txt, sitemap.xml, llms.txt and security.txt, as failure strings. A marola.dev URL
    inside them is read from base, so a local build checks its own files."""
    now = now or dt.datetime.now(dt.UTC)
    local = lambda u: base + u[len(DEFAULT_BASE) :] if u.startswith(DEFAULT_BASE) else u  # noqa: E731
    bad = []

    def get(path):
        try:
            return text(f"{base}{path}")
        except Exception as e:  # noqa: BLE001 - unreachable is the same story as missing
            return 0, str(e)

    def dead(urls, where):
        for u in dict.fromkeys(urls):
            try:
                code, _ = text(local(u))
            except Exception as e:  # noqa: BLE001
                code = str(e)
            if code != 200:
                bad.append(f"{where}: {u} answers {code}")

    code, robots = get("/robots.txt")
    if code != 200:
        bad.append(f"/robots.txt: {code}, no robots.txt")
    elif not re.search(r"(?mi)^sitemap:\s*https?://\S+", robots):
        bad.append("/robots.txt names no Sitemap")

    code, sitemap = get("/sitemap.xml")
    if code != 200:
        bad.append(f"/sitemap.xml: {code}, no sitemap")
    else:
        try:
            locs = [
                e.text or ""
                for e in ElementTree.fromstring(sitemap).findall("s:url/s:loc", SITEMAP_NS)
            ]
        except ElementTree.ParseError as e:
            locs = None
            bad.append(f"/sitemap.xml does not parse: {e}")
        if locs is not None and not locs:
            bad.append("/sitemap.xml lists no <loc>")
        dead(locs or [], "/sitemap.xml")

    code, llms = get("/llms.txt")
    if code != 200:
        bad.append(f"/llms.txt: {code}, no llms.txt")
    elif not llms.startswith("# "):
        bad.append("/llms.txt does not open with an H1")
    else:
        dead(LINK.findall(llms), "/llms.txt")

    code, sec = get("/.well-known/security.txt")
    if code != 200:
        bad.append(f"/.well-known/security.txt: {code}, no security.txt")
    else:
        if not re.search(r"(?m)^Contact: \S+", sec):
            bad.append("/.well-known/security.txt has no Contact")
        m = re.search(r"(?m)^Expires: (\S+)", sec)
        try:
            expires = dt.datetime.fromisoformat(m.group(1)) if m else None
        except ValueError:
            expires = None
        if expires is None:
            bad.append("/.well-known/security.txt has no valid Expires")
        elif expires <= now:
            bad.append(f"/.well-known/security.txt expired on {m.group(1)}: run site.yml")
    return bad


def check_board(area: str, day: str, board: dict) -> list[str]:
    """Every invariant that should hold for one published day, as failure strings."""
    bad = []
    where = f"{area}/{day}"
    if board.get("schema") != SCHEMA:
        bad.append(f"{where}: schema {board.get('schema')}, the page understands {SCHEMA}")
    beaches = board.get("beaches") or []
    if not beaches:
        bad.append(f"{where}: no beaches")
        return bad

    water_source = (board.get("sources") or {}).get("water")
    if water_source:
        # The label SiteBuilder writes when the provider returned nothing — the outage marker.
        if "no data returned" in water_source:
            bad.append(f"{where}: water provider {water_source!r} returned nothing")
        with_water = [b for b in beaches if (b.get("water") or {}).get("points")]
        if not with_water:
            bad.append(
                f"{where}: sources.water is {water_source!r} but no beach has a sampling point"
            )

    canary = CANARIES.get(area)
    if canary:
        named = [b for b in beaches if b.get("name") == canary]
        if not named:
            bad.append(f"{where}: {canary} is missing from the board")
        elif water_source and not (named[0].get("water") or {}).get("points"):
            bad.append(f"{where}: {canary} has no water sampling point")

    for b in beaches:
        if not (b.get("best") or {}).get("hour"):
            bad.append(f"{where}: {b.get('name')} has no best hour")
            break
    return bad


def check_site(base: str, get=fetch) -> list[str]:
    bad = []
    try:
        areas = get(f"{base}/data/areas.json")["areas"]
    except Exception as e:  # noqa: BLE001 - any failure here is the same story
        return [f"cannot read {base}/data/areas.json: {e}"]
    if not areas:
        return [f"{base}: areas.json lists no areas"]
    for a in areas:
        area = a["id"]
        try:
            latest = get(f"{base}/data/{area}/latest.json")
            for d in latest.get("days") or []:
                board = get(f"{base}/data/{area}/{d['file']}")
                bad += check_board(area, d["day"], board)
        except Exception as e:  # noqa: BLE001
            bad.append(f"{area}: cannot read a board: {e}")
    return bad


def self_test() -> int:
    fails = 0

    def ok(got, want, label):
        nonlocal fails
        if got == want:
            print(f"  ok   {label}")
        else:
            fails += 1
            print(f"  FAIL {label} — got {got!r}, want {want!r}")

    good = {
        "schema": 1,
        "sources": {"water": "IMA/SC"},
        "beaches": [
            {
                "name": "Praia do Campeche",
                "best": {"hour": "10:00"},
                "water": {"points": [{"id": "P06"}]},
            }
        ],
    }
    ok(check_board("floripa", "d", good), [], "a healthy board passes")

    # The exact shape marola.dev served while IMA was down: a named provider, zero points.
    blank = json.loads(json.dumps(good))
    blank["beaches"][0]["water"]["points"] = []
    msgs = check_board("floripa", "d", blank)
    ok(len(msgs), 2, "a provider with no points fails, and the canary fails too")
    ok(
        any("no beach has a sampling point" in m for m in msgs),
        True,
        "and names the provider it expected points from",
    )

    outage = json.loads(json.dumps(blank))
    outage["sources"]["water"] = "IMA/SC (no data returned)"
    ok(
        any("returned nothing" in m for m in check_board("floripa", "d", outage)),
        True,
        "SiteBuilder's own outage label is recognised",
    )

    nowater = json.loads(json.dumps(good))
    nowater["sources"]["water"] = None
    nowater["beaches"][0]["water"]["points"] = []
    ok(
        check_board("rio", "d", nowater),
        [],
        "an area with no water provider is not expected to have points",
    )

    missing = json.loads(json.dumps(good))
    missing["beaches"][0]["name"] = "Somewhere Else"
    ok(
        any("missing from the board" in m for m in check_board("floripa", "d", missing)),
        True,
        "the canary beach disappearing is a failure, not a shrug",
    )

    ok(
        any("schema" in m for m in check_board("floripa", "d", {**good, "schema": 2})),
        True,
        "a schema the page cannot read fails",
    )
    ok(
        any("no beaches" in m for m in check_board("x", "d", {"schema": 1})),
        True,
        "an empty board fails",
    )

    def broken(_url):
        raise urllib.error.URLError("down")

    ok(
        len(check_site("https://example.invalid", get=broken)),
        1,
        "an unreachable site is one clear failure",
    )

    base = "http://site.test"
    files = {
        "/robots.txt": "User-agent: *\nAllow: /\n\nSitemap: https://marola.dev/sitemap.xml\n",
        "/sitemap.xml": '<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/'
        'sitemap/0.9"><url><loc>https://marola.dev/</loc></url></urlset>',
        "/llms.txt": "# marola\n\n> x\n\n- [Map](https://marola.dev/): the map\n"
        "- [Docs](https://docs.marola.dev/): docs\n",
        "/.well-known/security.txt": "Contact: https://example.test\n"
        "Expires: 2027-11-10T00:00:00Z\n",
        "/": "<html>",
    }
    now = dt.datetime(2026, 11, 11, tzinfo=dt.UTC)

    def serve(over):
        site = {**files, **over}

        def text(url):
            if url == "https://docs.marola.dev/":
                return 200, ""
            path = url.removeprefix(base)
            return (200, site[path]) if site.get(path) is not None else (404, "")

        return text

    ok(check_meta(base, serve({}), now), [], "healthy crawl files pass")
    ok(
        check_meta(base, serve({"/robots.txt": "User-agent: *\nAllow: /\n"}), now),
        ["/robots.txt names no Sitemap"],
        "robots.txt without a Sitemap line fails",
    )
    ok(
        check_meta(base, serve({"/": None}), now),
        [
            "/sitemap.xml: https://marola.dev/ answers 404",
            "/llms.txt: https://marola.dev/ answers 404",
        ],
        "sitemap loc returning 404 fails, and so does the llms.txt link to it",
    )
    gone = files["/llms.txt"] + "- [Gone](https://marola.dev/gone.html): a page\n"
    ok(
        check_meta(base, serve({"/llms.txt": gone}), now),
        ["/llms.txt: https://marola.dev/gone.html answers 404"],
        "llms.txt link returning 404 fails",
    )
    ok(
        check_meta(base, serve({"/llms.txt": None}), now),
        ["/llms.txt: 404, no llms.txt"],
        "llms.txt missing fails",
    )
    ok(
        check_meta(base, serve({}), dt.datetime(2027, 12, 1, tzinfo=dt.UTC)),
        ["/.well-known/security.txt expired on 2027-11-10T00:00:00Z: run site.yml"],
        "security.txt past its Expires fails",
    )
    ok(
        check_meta(base, serve({"/.well-known/security.txt": None}), now),
        ["/.well-known/security.txt: 404, no security.txt"],
        "security.txt missing fails",
    )

    if fails:
        print(f"site_live_check self-test: {fails} failure(s)", file=sys.stderr)
        return 1
    print("site_live_check self-test: ok")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()

    bad = check_site(args.base.rstrip("/")) + check_meta(args.base.rstrip("/"))
    if not bad:
        print(f"site_live_check: {args.base} ok")
        return 0
    print(f"site_live_check: {len(bad)} problem(s) at {args.base}", file=sys.stderr)
    for m in bad:
        print(f"  - {m}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
