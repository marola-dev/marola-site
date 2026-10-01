#!/usr/bin/env python3
"""water: the agencies' bathing-water bulletins, fetched apart from the map's build (#4).

site/water.json lists each agency: the area whose build fetches it, the cron of its fetch (on the
agency's own publishing cadence), whether it answers only Brazilian addresses, and its hosts.
water.yml fetches each one and stores it on site-data as water/<id>.json; site.yml reads those
files, with the hosts of every agency that has one unreachable inside the build.

    python3 scripts/water.py plan          the agencies water.yml fetches now, as a JSON matrix:
                                           $SCHEDULE's (the cron that fired), $AGENCY (one id), or all
    python3 scripts/water.py hosts [DIR]   the agencies' hosts, one per line; with DIR, only those
                                           of agencies with a stored fetch (DIR/<id>.json) there
    python3 scripts/water.py verify FILE   exit 1 unless FILE is a fetch with sampling points
    python3 scripts/water.py report DIST   water quality per area of a built site/dist
    python3 scripts/water.py --self-test
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "site" / "water.json"
WORKFLOW = ROOT / ".github" / "workflows" / "water.yml"


def agencies(config: Path = CONFIG) -> list[dict]:
    return json.loads(config.read_text())["agencies"]


def cache_stem(name: str) -> str:
    """The app's cache file name for an agency (CachedWaterQualityClient.fileFor), minus .json."""
    return re.sub(r"[^A-Za-z0-9]+", "-", name).lower()


def stored_hosts(all_agencies: list[dict], stored: Path | None) -> list[str]:
    """Hosts to cut off in the map's build: an agency with nothing stored yet (before water.yml's
    first run) is left to the app's live fetch, so the build is never worse than without a store."""
    return [
        h
        for a in all_agencies
        if stored is None or (stored / f"{a['id']}.json").is_file()
        for h in a["hosts"]
    ]


def plan(all_agencies: list[dict], schedule: str, agency: str) -> list[dict]:
    if agency:
        picked = [a for a in all_agencies if a["id"] == agency]
        if not picked:
            raise SystemExit(f"::error::water: no agency {agency} in site/water.json")
        return picked
    if schedule:
        return [a for a in all_agencies if a["cron"] == schedule]
    return all_agencies


def verify(path: Path) -> tuple[bool, str]:
    """Whether the fetch the app wrote is usable: it writes the file only when an agency answered
    with points, so a missing file is a failed fetch."""
    try:
        points = json.loads(path.read_text()).get("points") or []
    except (OSError, ValueError) as e:
        return False, f"{path.name}: no fetch ({e.__class__.__name__})"
    if not points:
        return False, f"{path.name}: the agency answered with no sampling points"
    dates = [s.get("sampled_on", "") for p in points for s in p.get("samples") or []]
    return (
        True,
        f"{path.name}: {len(points)} sampling points, newest sample {max(dates, default='?')}",
    )


def report(dist: Path) -> list[str]:
    """One line per built area: its beaches, how many carry sampling points, and from whom."""
    lines = []
    for area in json.loads((dist / "data" / "areas.json").read_text())["areas"]:
        aid = area["id"]
        # A missing board is the "Required files" step's to fail on; here it only reads as no data.
        try:
            latest = json.loads((dist / "data" / aid / "latest.json").read_text())
            board = json.loads((dist / "data" / aid / latest["days"][0]["file"]).read_text())
        except (OSError, ValueError, KeyError, IndexError):
            board = {}
        beaches = board.get("beaches") or []
        wet = [b["water"] for b in beaches if (b.get("water") or {}).get("points")]
        sources = ", ".join(sorted({w.get("source") or "?" for w in wet})) or "none"
        lines.append(f"{aid}: {len(wet)}/{len(beaches)} beaches with water quality ({sources})")
    return lines


def self_test() -> int:
    fails = 0

    def ok(cond: bool, label: str) -> None:
        nonlocal fails
        print(("  ok   " if cond else "  FAIL ") + label)
        fails += not cond

    real = agencies()
    ids = [a["id"] for a in real]
    ok(len(ids) == len(set(ids)), "site/water.json: agency ids are unique")
    ok(
        all(a["id"] == cache_stem(a["name"]) for a in real),
        "site/water.json: each id is the app's cache file name for that agency",
    )
    crons = [a["cron"] for a in real]
    ok(
        len(crons) == len(set(crons)),
        "site/water.json: one cron per agency, so a fired cron names one",
    )
    fired = set(re.findall(r'cron:\s*"([^"]+)"', WORKFLOW.read_text()))
    ok(fired == set(crons), "water.yml's schedule is exactly site/water.json's crons")
    areas = {a["id"] for a in json.loads((ROOT / "site" / "areas.json").read_text())}
    ok(all(a["area"] in areas for a in real), "every agency's area is in site/areas.json")

    ok(
        [a["id"] for a in plan(real, real[1]["cron"], "")] == [ids[1]],
        "a fired cron fetches its agency only",
    )
    ok(
        [a["id"] for a in plan(real, "", ids[2])] == [ids[2]],
        "a dispatch with an id fetches that one",
    )
    ok(len(plan(real, "", "")) == len(real), "a dispatch without one, or a PR, fetches them all")
    try:
        plan(real, "", "nowhere")
        ok(False, "an unknown id is an error")
    except SystemExit:
        ok(True, "an unknown id is an error")

    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        ok(stored_hosts(real, None) == [h for a in real for h in a["hosts"]], "no DIR: every host")
        ok(stored_hosts(real, t) == [], "nothing stored yet: no host cut off, the app fetches live")
        (t / f"{ids[0]}.json").write_text("{}")
        ok(
            stored_hosts(real, t) == real[0]["hosts"],
            "a stored agency's hosts are cut off, the rest not",
        )
        (t / f"{ids[0]}.json").unlink()
        good = t / "inea-rj.json"
        good.write_text(
            json.dumps({"version": 1, "points": [{"samples": [{"sampled_on": "2026-09-21"}]}]})
        )
        empty = t / "inema-ba.json"
        empty.write_text(json.dumps({"version": 1, "points": []}))
        ok(
            verify(good) == (True, "inea-rj.json: 1 sampling points, newest sample 2026-09-21"),
            "a fetch with points verifies",
        )
        ok(not verify(empty)[0], "an empty fetch does not")
        ok(not verify(t / "ima-sc.json")[0], "no file (the agency never answered) does not")

        dist = t / "dist"
        (dist / "data").mkdir(parents=True)
        (dist / "data" / "areas.json").write_text(
            json.dumps({"areas": [{"id": "rio"}, {"id": "floripa"}, {"id": "ghost"}]})
        )
        wet = {"name": "b", "water": {"source": "IMA/SC", "points": [{"point": "p"}]}}
        dry = {"name": "b", "water": None}
        for aid, beaches in {"rio": [dry, dry], "floripa": [wet, dry]}.items():
            (dist / "data" / aid).mkdir()
            (dist / "data" / aid / "latest.json").write_text(
                json.dumps({"days": [{"file": "d.json"}]})
            )
            (dist / "data" / aid / "d.json").write_text(json.dumps({"beaches": beaches}))
        ok(
            report(dist)
            == [
                "rio: 0/2 beaches with water quality (none)",
                "floripa: 1/2 beaches with water quality (IMA/SC)",
                "ghost: 0/0 beaches with water quality (none)",
            ],
            "the report counts beaches with points per area, and a missing board as none",
        )

    print("water self-test: " + ("ok" if fails == 0 else f"{fails} failure(s)"))
    return 0 if fails == 0 else 1


def main(argv: list[str]) -> int:
    match argv:
        case ["--self-test"]:
            return self_test()
        case ["plan"]:
            picked = plan(agencies(), os.environ.get("SCHEDULE", ""), os.environ.get("AGENCY", ""))
            print(json.dumps(picked, separators=(",", ":")))
            return 0
        case ["hosts", *stored] if len(stored) <= 1:
            hosts = stored_hosts(agencies(), Path(stored[0]) if stored else None)
            if hosts:
                print("\n".join(hosts))
            return 0
        case ["verify", path]:
            good, line = verify(Path(path))
            print(line if good else f"::error::water: {line}")
            return 0 if good else 1
        case ["report", dist]:
            print("\n".join(report(Path(dist))))
            return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
