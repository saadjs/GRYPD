"""Shared helpers for the GRYPD catalog pipeline."""

import hashlib
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRATCH_DIR = os.path.join(ROOT, "scratch_dtable")
DIST_DIR = os.environ.get("GRYPD_DIST_DIR", os.path.join(ROOT, "dist"))
APP_RESOURCES_DIR = os.environ.get(
    "GRYPD_APP_RESOURCES_DIR", os.path.join(ROOT, "app", "GRYPD", "Resources")
)
CONTENT = os.path.join(SCRATCH_DIR, "content.json")
CATALOG = os.path.join(ROOT, "catalog", "strength.json")
# Negative cache: Apple workout IDs whose links are confirmed delisted (404).
# enrich.py skips these so each run only hits the network for links it has
# never seen — the mirror of the positive resume via CATALOG. Committed state.
DELISTED = os.path.join(ROOT, "catalog", "delisted.json")

VALID_FOCUS = {"upper-body", "lower-body", "total-body"}
VALID_DURATIONS = {10, 11, 20, 21, 30, 31}

# --- Dumbbell-weight buckets ------------------------------------------------
# The raw `dumbbells` facet encodes quantity + weight in one messy slug
# (e.g. "2-heavy", "1-medium-heavy", "bodyweight", "optional"). For filtering
# we collapse each workout to a subset of these four buckets. See the app's
# FilterSheet "Dumbbell" section, which mirrors this vocabulary.
VALID_DUMBBELL_LOAD = ("light", "medium", "heavy", "bodyweight")
# Weight tiers in descending "heaviness" — a single raw slug resolves to the
# heaviest tier whose name it contains, so compounds fold to the heavier bucket
# ("2-medium-heavy" -> heavy, "2-light-medium" -> medium).
_DUMBBELL_TIERS = ("heavy", "medium", "light")
# Slugs whose name carries no light/medium/heavy word — mapped explicitly.
_NAMED_DUMBBELL_SLUG = {
    "1-challenging": "medium",
    "2-you-can-curl-and-press": "medium",
    "2-you-can-lift-to-the-side": "medium",  # i.e. "light/medium" -> heavier
    "bodyweight": "bodyweight",
}
# `optional` is ambiguous per-slug, so these workouts are classified by id.
_OPTIONAL_DUMBBELL_LOAD = {
    "1577854883": ["heavy"],            # ep16 Amir
    "1536717998": ["heavy"],            # ep4  Betina
    "1554611034": ["medium", "heavy"],  # ep9  Kyle
    "1569935664": ["light", "medium"],  # ep14 Kyle
    "1591386110": ["heavy"],            # ep30 Kyle
}


def _dumbbell_slug_bucket(slug):
    """The bucket for one raw dumbbell slug, or None if unrecognized."""
    if slug in _NAMED_DUMBBELL_SLUG:
        return _NAMED_DUMBBELL_SLUG[slug]
    if slug == "optional":
        return None  # resolved per-id via _OPTIONAL_DUMBBELL_LOAD, not per-slug
    for tier in _DUMBBELL_TIERS:  # heaviest first
        if tier in slug:
            return tier
    return None


def dumbbell_load(raw_slugs, *, workout_id):
    """Collapse a workout's raw `dumbbells` slugs to ordered weight buckets.

    Never raises: an unclassifiable workout resolves to `[]` and logs a warning
    so the weekly run surfaces new `optional`/joke slugs without blocking publish.
    """
    if workout_id in _OPTIONAL_DUMBBELL_LOAD:
        return list(_OPTIONAL_DUMBBELL_LOAD[workout_id])

    buckets = set()
    for slug in raw_slugs or []:
        bucket = _dumbbell_slug_bucket(slug)
        if bucket is not None:
            buckets.add(bucket)

    # Option B: a workout that needs any weights is never "bodyweight only".
    if buckets & set(_DUMBBELL_TIERS):
        buckets.discard("bodyweight")

    if not buckets:
        print(f"  WARN dumbbellLoad empty for {workout_id}: slugs={list(raw_slugs or [])}")

    return [b for b in VALID_DUMBBELL_LOAD if b in buckets]


def load_json(path):
    with open(path) as f:
        return json.load(f)


def display_path(path):
    return os.path.relpath(path, ROOT)


def write_json(path, obj, *, indent=None, compact=False):
    separators = (",", ":") if compact else None
    with open(path, "w") as f:
        json.dump(obj, f, indent=indent, ensure_ascii=False, separators=separators)


def sha256_10(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:10]


def slugify(s):
    return re.sub(r"[^a-z0-9]+", "-", (s or "").lower()).strip("-")


def load_table(name):
    d = load_json(CONTENT)
    t = [x for x in d["tables"] if x["name"] == name][0]
    keyname = {c["key"]: c["name"] for c in t["columns"]}
    opts = {}
    for c in t["columns"]:
        data = c.get("data") or {}
        if "options" in data:
            opts[c["name"]] = {o["id"]: o["name"] for o in data["options"]}
    return t, keyname, opts


def resolve(val, omap):
    if val is None:
        return None
    if isinstance(val, list):
        return [omap.get(v, v) for v in val]
    return omap.get(val, val)


def resolved_slugs(r, nk, opts, field):
    return [slugify(x) for x in (resolve(r.get(nk[field]), opts.get(field, {})) or [])]


def text_value(value):
    if isinstance(value, dict):
        return (value.get("text") or value.get("preview") or "").strip() or None
    if isinstance(value, str):
        return value.strip() or None
    return None


def row_facets(r, nk, opts, *, body_focus, workout_id):
    dumbbells = resolved_slugs(r, nk, opts, "Dumbbells")
    return {
        "bodyFocus": body_focus,
        "muscleGroups": resolved_slugs(r, nk, opts, "Muscle Groups"),
        "equipment": resolved_slugs(r, nk, opts, "Equipment"),
        "dumbbells": dumbbells,
        "dumbbellLoad": dumbbell_load(dumbbells, workout_id=workout_id),
    }


def apple_body_focus(ap):
    return slugify((ap["bodyFocuses"] or [None])[0])


def apple_workout_record(r, nk, opts, ap, slug, wid):
    return {
        "id": wid,
        "discipline": "strength",
        "title": ap["name"],
        "trainer": slugify(resolve(r.get(nk["Trainer"]), opts.get("Trainer", {}))),
        "durationMinutes": ap["durationMinutes"],
        "episode": ap["episode"],
        "appleUrl": f"https://fitness.apple.com/us/workout/{slug}/{wid}",
        "description": ap["description"],
        "releaseDate": ap.get("releaseDate"),
        "facets": row_facets(r, nk, opts, body_focus=apple_body_focus(ap), workout_id=wid),
        "moves": resolved_slugs(r, nk, opts, "Types of Moves"),
    }


def fallback_workout_record(r, nk, opts):
    trainer_label = resolve(r.get(nk["Trainer"]), opts.get("Trainer", {}))
    link = r.get(nk["Link"])
    summary = (
        text_value(r.get(nk["Description"]))
        or text_value(r.get(nk["Format"]))
        or text_value(r.get(nk["Detailed Moves"]))
    )
    wid = f"seatable-{r['_id']}"
    record = {
        "id": wid,
        "discipline": "strength",
        "title": f"Strength with {trainer_label}",
        "trainer": slugify(trainer_label),
        "durationMinutes": durbucket(resolve(r.get(nk["Duration"]), opts.get("Duration", {}))),
        "episode": r.get(nk["Ep"]),
        "description": summary,
        "releaseDate": r.get(nk["Date"]),
        "facets": row_facets(
            r,
            nk,
            opts,
            body_focus=slugify(resolve(r.get(nk["Body Focus"]), opts.get("Body Focus", {}))),
            workout_id=wid,
        ),
        "moves": resolved_slugs(r, nk, opts, "Types of Moves"),
    }
    if link:
        record["appleUrl"] = link.replace("/ca/", "/us/")
    return record


def row_is_publishable_fallback(r, nk, opts):
    required_scalar_fields = ["Trainer", "Duration", "Body Focus"]
    for field in required_scalar_fields:
        if not resolve(r.get(nk[field]), opts.get(field, {})):
            return False
    # "Types of Moves" is intentionally NOT required: a new weekly workout is
    # publishable from its trainer/duration/focus/muscle-group facets alone, so
    # it appears in the catalog before its exercise list is entered.
    required_list_fields = ["Muscle Groups"]
    for field in required_list_fields:
        if not resolve(r.get(nk[field]), opts.get(field, {})):
            return False
    return True


def durbucket(x):
    try:
        return int(round(int(re.sub(r"[^0-9]", "", str(x))) / 10.0) * 10)
    except Exception:
        return None


def st_key(r, nk, opts):
    tr = slugify(resolve(r.get(nk["Trainer"]), opts.get("Trainer", {})))
    ep = r.get(nk["Ep"])
    dur = durbucket(resolve(r.get(nk["Duration"]), opts.get("Duration", {})))
    bf = slugify(resolve(r.get(nk["Body Focus"]), opts.get("Body Focus", {})))
    return (tr, ep, dur, bf)


def ap_key(rec):
    tr = rec["trainer"]
    ep = rec["episode"]
    dur = durbucket(rec["durationMinutes"])
    bf = rec["facets"]["bodyFocus"]
    return (tr, ep, dur, bf)
