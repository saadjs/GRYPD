#!/usr/bin/env python3
"""GRYPD enricher: SeaTable row -> Apple embedded-cache canonical data -> merged catalog JSON."""

import html
import json
import random
import re
import sys
import time
import urllib.error
import urllib.request

from common import (
    CATALOG,
    apple_workout_record,
    display_path,
    load_json,
    load_table,
    write_json,
)

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"


def fetch_apple(slug, wid):
    """Returns (record|None, status): status is 'ok','404', or 'error' (transient)."""
    url = f"https://fitness.apple.com/us/workout/{slug}/{wid}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    h = None
    for attempt in range(4):
        try:
            h = urllib.request.urlopen(req, timeout=25).read().decode("utf-8", "ignore")
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None, "404"  # genuinely de-listed
            time.sleep(1.5 * (attempt + 1) + random.random())  # 429/5xx: back off
        except Exception:
            time.sleep(1.5 * (attempt + 1) + random.random())
    if h is None:
        return None, "error"  # transient exhaustion -> retry later, NOT delisted
    m = re.search(r'shoebox-media-api-cache-amp-fitness">(.*?)</script>', h, re.S)
    if not m:
        return None, "error"
    cache = json.loads(html.unescape(m.group(1).strip()))
    for v in cache.values():
        try:
            value = json.loads(v)
        except json.JSONDecodeError:
            continue
        for r in value.get("d", []):
            if r.get("type") == "workouts" and r.get("id") == str(wid):
                a = r["attributes"]
                # NOTE: Apple's artwork (a['artworks']) is intentionally NOT read.
                # Fitness+ imagery is Apple-copyrighted and unlicensed for third-party
                # apps; the app renders its own generative artwork instead.
                return {
                    "name": a.get("name"),
                    "bodyFocuses": a.get("bodyFocuses"),
                    "durationMinutes": round(a.get("durationInMilliseconds", 0) / 60000),
                    "episode": a.get("episodeNumber"),
                    "description": (a.get("description") or {}).get("standard"),
                    "releaseDate": a.get("releaseDate"),  # ISO "YYYY-MM-DD"
                }, "ok"
    return None, "error"


def main(limit):
    t, kn, opts = load_table("Strength")
    nk = {v: k for k, v in kn.items()}
    # resume: keep already-enriched records, skip their ids
    try:
        out = load_json(CATALOG)
    except OSError:
        out = []
    have = {r["id"] for r in out}
    done = 0
    delisted = errors = 0
    for r in t["rows"]:
        link = r.get(nk["Link"])
        if not link:
            continue
        m = re.search(r"/workout/([a-z0-9-]+)/(\d{9,10})", link)
        if not m:
            continue
        slug, wid = m.group(1), m.group(2)
        if wid in have:
            continue
        ap, status = fetch_apple(slug, wid)
        if status == "404":
            delisted += 1
            print(f"  DELISTED {wid} {slug}", file=sys.stderr)
            continue
        if not ap:
            errors += 1
            print(f"  RETRY-LATER {wid} {slug}", file=sys.stderr)
            continue
        rec = apple_workout_record(r, nk, opts, ap, slug, wid)
        out.append(rec)
        done += 1
        print(
            f"  OK {wid}  {rec['title']}  [{rec['facets']['bodyFocus']}]  "
            f"muscles={len(rec['facets']['muscleGroups'])} moves={len(rec['moves'])}"
        )
        time.sleep(0.6 + random.random() * 0.4)  # gentler pacing to avoid throttling
        if done >= limit:
            break
    out.sort(key=lambda r: (r["trainer"], int(r["id"])))
    write_json(CATALOG, out, indent=1)
    print(
        f"\nNEW {done}  |  TOTAL {len(out)}  |  DELISTED(404) {delisted}  |  "
        f"RETRY-LATER {errors}  ->  {display_path(CATALOG)}"
    )


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 12)
