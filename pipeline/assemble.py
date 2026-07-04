#!/usr/bin/env python3
"""Validate the strength catalog (firewall), build taxonomy, and emit content-addressed
artifacts + manifest into dist/ (the static hosting payload)."""

import datetime
import hashlib
import json
import os
import re
import sys

from common import (
    CATALOG,
    DIST_DIR,
    VALID_DURATIONS,
    VALID_FOCUS,
    ap_key,
    fallback_workout_record,
    load_json,
    load_table,
    row_is_publishable_fallback,
    slugify,
    st_key,
    write_json,
)

SCHEMA_VERSION = 1


def build_label_maps():
    """slug -> human label, from SeaTable option names."""
    t, kn, opts = load_table("Strength")
    m = {
        "muscleGroups": {},
        "equipment": {},
        "dumbbells": {},
        "bodyFocus": {},
        "trainers": {},
        "moves": {},
    }
    src = {
        "Muscle Groups": "muscleGroups",
        "Equipment": "equipment",
        "Dumbbells": "dumbbells",
        "Body Focus": "bodyFocus",
        "Trainer": "trainers",
        "Types of Moves": "moves",
    }
    for col, key in src.items():
        for _id, name in opts.get(col, {}).items():
            m[key][slugify(name)] = name
    return m


def firewall(cat):
    errs = []
    if len(cat) < 400:
        errs.append(f"volume collapse: only {len(cat)} records")
    ids = [r["id"] for r in cat]
    if len(ids) != len(set(ids)):
        errs.append("duplicate ids present")
    apple_ids = []
    for r in cat:
        m = re.search(r"/(\d{9,10})(?:\?|$)", r.get("appleUrl") or "")
        if m:
            apple_ids.append(m.group(1))
    if len(apple_ids) != len(set(apple_ids)):
        errs.append("duplicate Apple workout URLs present")
    for r in cat:
        w = r.get("id", "?")
        if not (
            re.fullmatch(r"\d{9,10}", r.get("id", ""))
            or re.fullmatch(r"seatable-[A-Za-z0-9_-]+", r.get("id", ""))
        ):
            errs.append(f"{w}: bad id")
        if r.get("appleUrl") and not r.get("appleUrl", "").startswith("https://fitness.apple.com/"):
            errs.append(f"{w}: bad appleUrl")
        if r.get("durationMinutes") not in VALID_DURATIONS:
            errs.append(f"{w}: bad duration {r.get('durationMinutes')}")
        if r["facets"].get("bodyFocus") not in VALID_FOCUS:
            errs.append(f"{w}: bad bodyFocus")
        if not r["facets"].get("muscleGroups"):
            errs.append(f"{w}: no muscleGroups")
        if not r.get("moves"):
            errs.append(f"{w}: no moves")
    return errs


def add_alias(rec, alias):
    if rec.get("id") == alias:
        return
    aliases = rec.setdefault("aliases", [])
    if alias not in aliases:
        aliases.append(alias)


def apple_id_from_row(r, nk):
    m = re.search(r"/(\d{9,10})", r.get(nk["Link"]) or "")
    return m.group(1) if m else None


def build_complete_catalog(cat):
    t, kn, opts = load_table("Strength")
    nk = {v: k for k, v in kn.items()}
    consumed = set()

    linked_rows_by_id = {}
    for r in t["rows"]:
        apple_id = apple_id_from_row(r, nk)
        if apple_id:
            linked_rows_by_id.setdefault(apple_id, []).append(r)

    # Directly linked rows already represented by canonical Apple records.
    for rec in cat:
        if rec["id"] in linked_rows_by_id:
            for row in linked_rows_by_id[rec["id"]]:
                row_id = row["_id"]
                consumed.add(row_id)
                add_alias(rec, f"seatable-{row_id}")

    # Catalog records that are not directly linked still correspond to a
    # SeaTable row. Consume one matching SeaTable key for each so fallback
    # rows do not duplicate the same Apple IDs.
    unconsumed_by_key = {}
    for r in t["rows"]:
        if r["_id"] in consumed or apple_id_from_row(r, nk):
            continue
        unconsumed_by_key.setdefault(st_key(r, nk, opts), []).append(r)

    for rec in cat:
        if rec["id"] in linked_rows_by_id:
            continue
        cands = unconsumed_by_key.get(ap_key(rec), [])
        if cands:
            row_id = cands.pop(0)["_id"]
            consumed.add(row_id)
            add_alias(rec, f"seatable-{row_id}")

    fallback_rows = [
        r
        for r in t["rows"]
        if r["_id"] not in consumed and row_is_publishable_fallback(r, nk, opts)
    ]
    linked_fallbacks_by_id = {}
    fallbacks = []
    for r in fallback_rows:
        apple_id = apple_id_from_row(r, nk)
        if apple_id:
            linked_fallbacks_by_id.setdefault(apple_id, []).append(r)
        else:
            fallbacks.append(fallback_workout_record(r, nk, opts))
    for rows in linked_fallbacks_by_id.values():
        fallback = fallback_workout_record(rows[0], nk, opts)
        for row in rows:
            add_alias(fallback, f"seatable-{row['_id']}")
        fallbacks.append(fallback)
    complete = cat + fallbacks
    complete.sort(
        key=lambda r: (
            r.get("releaseDate") is None,
            r.get("releaseDate") or "",
            r.get("trainer") or "",
            r.get("episode") or 0,
            r.get("id") or "",
        ),
        reverse=True,
    )
    return complete, len(fallbacks)


def used_taxonomy(cat, labels):
    """collect only slugs actually used, with labels (fallback: title-cased slug)."""
    used = {
        k: {} for k in ["bodyFocus", "muscleGroups", "equipment", "dumbbells", "trainers", "moves"]
    }

    def add(bucket, slug):
        if slug:
            used[bucket][slug] = labels[bucket].get(slug, slug.replace("-", " ").title())

    for r in cat:
        add("bodyFocus", r["facets"].get("bodyFocus"))
        add("trainers", r.get("trainer"))
        for x in r["facets"].get("muscleGroups", []):
            add("muscleGroups", x)
        for x in r["facets"].get("equipment", []):
            add("equipment", x)
        for x in r["facets"].get("dumbbells", []):
            add("dumbbells", x)
        for x in r.get("moves", []):
            add("moves", x)
    used = {k: dict(sorted(v.items())) for k, v in used.items()}
    used["disciplines"] = {"strength": "Strength"}
    return used


def write_addressed(dirpath, name, obj):
    body = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode()
    h = hashlib.sha256(body).hexdigest()[:10]
    fname = f"{name}.{h}.json"
    with open(os.path.join(dirpath, fname), "wb") as f:
        f.write(body)
    return fname, h, len(body)


def main():
    cat = load_json(CATALOG)
    # Defensive: never publish Apple-copyrighted artwork URLs, even if an older
    # catalog cache still carries them. The app renders its own artwork.
    for r in cat:
        r.pop("imageTemplate", None)
    cat, fallback_count = build_complete_catalog(cat)
    errs = firewall(cat)
    if errs:
        print("FIREWALL: HARD-FAIL — publishing nothing. Issues:")
        for e in errs[:20]:
            print("  -", e)
        sys.exit(1)
    print(
        f"FIREWALL: PASS ({len(cat)} strength records, {fallback_count} SeaTable fallback records)"
    )

    os.makedirs(DIST_DIR, exist_ok=True)
    labels = build_label_maps()
    tax = used_taxonomy(cat, labels)
    tax_file, tax_hash, tax_bytes = write_addressed(DIST_DIR, "taxonomy", tax)
    cat_file, cat_hash, cat_bytes = write_addressed(DIST_DIR, "strength", cat)

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "catalogVersion": datetime.datetime.now(datetime.UTC).strftime("%Y.%W"),
        "taxonomy": {"file": tax_file, "sha256_10": tax_hash, "bytes": tax_bytes},
        "disciplines": [
            {
                "slug": "strength",
                "label": "Strength",
                "file": cat_file,
                "sha256_10": cat_hash,
                "count": len(cat),
                "bytes": cat_bytes,
            }
        ],
    }
    write_json(os.path.join(DIST_DIR, "manifest.json"), manifest, indent=1)
    print("\nARTIFACTS written to dist/:")
    print("  manifest.json")
    print(f"  {cat_file}   ({len(cat)} workouts, {cat_bytes // 1024} KB)")
    print(
        f"  {tax_file}   (muscle:{len(tax['muscleGroups'])} moves:{len(tax['moves'])} "
        f"trainers:{len(tax['trainers'])} focus:{len(tax['bodyFocus'])} "
        f"equip:{len(tax['equipment'])} dumbbells:{len(tax['dumbbells'])})"
    )


if __name__ == "__main__":
    main()
