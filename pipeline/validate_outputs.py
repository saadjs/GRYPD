#!/usr/bin/env python3
"""Validate generated catalog JSON against the app-facing contract."""

import os
import re
import sys

from common import (
    APP_RESOURCES_DIR,
    DIST_DIR,
    VALID_DUMBBELL_LOAD,
    VALID_DURATIONS,
    VALID_FOCUS,
    load_json,
    sha256_10,
)

TAXONOMY_BUCKETS = {
    "bodyFocus",
    "muscleGroups",
    "equipment",
    "dumbbells",
    "trainers",
    "moves",
    "disciplines",
}


def is_string_list(value):
    return isinstance(value, list) and all(isinstance(item, str) and item for item in value)


def require(condition, errors, message):
    if not condition:
        errors.append(message)


def load_required_json(path, errors, label):
    try:
        return load_json(path)
    except OSError as e:
        errors.append(f"{label} could not be read: {e}")
    except ValueError as e:
        errors.append(f"{label} is not valid JSON: {e}")
    return None


def validate_manifest(manifest, errors):
    require(isinstance(manifest, dict), errors, "manifest must be object")
    if not isinstance(manifest, dict):
        return
    require(
        isinstance(manifest.get("schemaVersion"), int), errors, "manifest.schemaVersion must be int"
    )
    require(
        isinstance(manifest.get("generatedAt"), str), errors, "manifest.generatedAt must be string"
    )
    require(
        isinstance(manifest.get("catalogVersion"), str),
        errors,
        "manifest.catalogVersion must be string",
    )
    validate_file_ref(manifest.get("taxonomy"), errors, "manifest.taxonomy")
    disciplines = manifest.get("disciplines")
    require(
        isinstance(disciplines, list) and disciplines,
        errors,
        "manifest.disciplines must be non-empty",
    )
    if isinstance(disciplines, list):
        for index, discipline in enumerate(disciplines):
            prefix = f"manifest.disciplines[{index}]"
            require(isinstance(discipline, dict), errors, f"{prefix} must be object")
            if not isinstance(discipline, dict):
                continue
            require(discipline.get("slug") == "strength", errors, f"{prefix}.slug must be strength")
            require(
                isinstance(discipline.get("label"), str), errors, f"{prefix}.label must be string"
            )
            validate_file_ref(discipline, errors, prefix)
            require(isinstance(discipline.get("count"), int), errors, f"{prefix}.count must be int")


def validate_file_ref(ref, errors, prefix):
    require(isinstance(ref, dict), errors, f"{prefix} must be object")
    if not isinstance(ref, dict):
        return False
    require(isinstance(ref.get("file"), str), errors, f"{prefix}.file must be string")
    require(
        isinstance(ref.get("sha256_10"), str) and re.fullmatch(r"[0-9a-f]{10}", ref["sha256_10"]),
        errors,
        f"{prefix}.sha256_10 must be 10 lowercase hex chars",
    )
    require(isinstance(ref.get("bytes"), int), errors, f"{prefix}.bytes must be int")
    return (
        isinstance(ref.get("file"), str)
        and isinstance(ref.get("sha256_10"), str)
        and bool(re.fullmatch(r"[0-9a-f]{10}", ref["sha256_10"]))
        and isinstance(ref.get("bytes"), int)
    )


def validate_workouts(workouts, taxonomy, errors):
    require(
        isinstance(workouts, list) and workouts, errors, "strength catalog must be non-empty array"
    )
    if not isinstance(workouts, list):
        return

    ids = []
    aliases = []
    for index, workout in enumerate(workouts):
        prefix = f"strength[{index}]"
        require(isinstance(workout, dict), errors, f"{prefix} must be object")
        if not isinstance(workout, dict):
            continue

        workout_id = workout.get("id")
        ids.append(workout_id)
        require(
            isinstance(workout_id, str)
            and (
                re.fullmatch(r"\d{9,10}", workout_id)
                or re.fullmatch(r"seatable-[A-Za-z0-9_-]+", workout_id)
            ),
            errors,
            f"{prefix}.id has invalid shape",
        )
        require(
            workout.get("discipline") == "strength", errors, f"{prefix}.discipline must be strength"
        )
        for key in ("title", "trainer"):
            require(
                isinstance(workout.get(key), str) and workout[key],
                errors,
                f"{prefix}.{key} missing",
            )
        require(
            workout.get("durationMinutes") in VALID_DURATIONS,
            errors,
            f"{prefix}.durationMinutes invalid",
        )
        require(
            workout.get("episode") is None or isinstance(workout.get("episode"), int),
            errors,
            f"{prefix}.episode must be int or null",
        )
        require(
            workout.get("appleUrl") is None
            or (
                isinstance(workout.get("appleUrl"), str)
                and workout["appleUrl"].startswith("https://fitness.apple.com/")
            ),
            errors,
            f"{prefix}.appleUrl invalid",
        )
        require(
            workout.get("releaseDate") is None
            or (
                isinstance(workout.get("releaseDate"), str)
                and re.fullmatch(r"\d{4}-\d{2}-\d{2}", workout["releaseDate"])
            ),
            errors,
            f"{prefix}.releaseDate invalid",
        )
        require(
            workout.get("description") is None or isinstance(workout.get("description"), str),
            errors,
            f"{prefix}.description must be string or null",
        )
        require(
            is_string_list(workout.get("moves")),
            errors,
            f"{prefix}.moves must be non-empty strings",
        )
        require(
            workout.get("moveSequence") is None or is_string_list(workout.get("moveSequence")),
            errors,
            f"{prefix}.moveSequence must be string array or omitted",
        )
        require(
            workout.get("coachNotes") is None or isinstance(workout.get("coachNotes"), str),
            errors,
            f"{prefix}.coachNotes must be string or omitted",
        )

        workout_aliases = workout.get("aliases")
        require(
            workout_aliases is None or is_string_list(workout_aliases),
            errors,
            f"{prefix}.aliases must be string array or omitted",
        )
        if isinstance(workout_aliases, list):
            aliases.extend(workout_aliases)

        facets = workout.get("facets")
        require(isinstance(facets, dict), errors, f"{prefix}.facets must be object")
        if isinstance(facets, dict):
            require(
                facets.get("bodyFocus") in VALID_FOCUS, errors, f"{prefix}.facets.bodyFocus invalid"
            )
            require(
                is_string_list(facets.get("muscleGroups")),
                errors,
                f"{prefix}.facets.muscleGroups must be non-empty strings",
            )
            require(
                is_string_list(facets.get("equipment")),
                errors,
                f"{prefix}.facets.equipment must be non-empty strings",
            )
            require(
                facets.get("dumbbells") is None or is_string_list(facets.get("dumbbells")),
                errors,
                f"{prefix}.facets.dumbbells must be string array or omitted",
            )
            dumbbell_load = facets.get("dumbbellLoad")
            require(
                isinstance(dumbbell_load, list)
                and all(v in VALID_DUMBBELL_LOAD for v in dumbbell_load),
                errors,
                f"{prefix}.facets.dumbbellLoad must be a list of {sorted(VALID_DUMBBELL_LOAD)}",
            )

        validate_taxonomy_coverage(workout, taxonomy, errors, prefix)

    require(len(ids) == len(set(ids)), errors, "strength catalog has duplicate ids")
    require(not (set(ids) & set(aliases)), errors, "aliases must not duplicate canonical ids")


def validate_taxonomy_coverage(workout, taxonomy, errors, prefix):
    if not isinstance(taxonomy, dict):
        return
    for bucket in ("trainers", "bodyFocus", "muscleGroups", "equipment", "dumbbells", "moves"):
        if not isinstance(taxonomy.get(bucket), dict):
            return
    require(
        workout.get("trainer") in taxonomy["trainers"], errors, f"{prefix}.trainer missing taxonomy"
    )
    facets = workout.get("facets") or {}
    require(
        facets.get("bodyFocus") in taxonomy["bodyFocus"],
        errors,
        f"{prefix}.bodyFocus missing taxonomy",
    )
    for bucket, slugs in (
        ("muscleGroups", facets.get("muscleGroups") or []),
        ("equipment", facets.get("equipment") or []),
        ("dumbbells", facets.get("dumbbells") or []),
        ("moves", workout.get("moves") or []),
    ):
        for slug in slugs:
            require(slug in taxonomy[bucket], errors, f"{prefix}.{bucket}.{slug} missing taxonomy")


def validate_taxonomy(taxonomy, errors):
    require(isinstance(taxonomy, dict), errors, "taxonomy must be object")
    if not isinstance(taxonomy, dict):
        return
    require(set(taxonomy) == TAXONOMY_BUCKETS, errors, "taxonomy buckets do not match app contract")
    for bucket in TAXONOMY_BUCKETS:
        labels = taxonomy.get(bucket)
        require(isinstance(labels, dict), errors, f"taxonomy.{bucket} must be object")
        if isinstance(labels, dict):
            for slug, label in labels.items():
                require(isinstance(slug, str) and slug, errors, f"taxonomy.{bucket} has bad slug")
                require(
                    isinstance(label, str) and label, errors, f"taxonomy.{bucket}.{slug} bad label"
                )
    require(
        taxonomy.get("disciplines", {}).get("strength") == "Strength", errors, "missing discipline"
    )


def manifest_file_refs(manifest):
    if not isinstance(manifest, dict):
        return []
    refs = []
    taxonomy = manifest.get("taxonomy")
    if valid_file_ref(taxonomy):
        refs.append(taxonomy)
    disciplines = manifest.get("disciplines")
    if isinstance(disciplines, list):
        refs.extend(ref for ref in disciplines if valid_file_ref(ref))
    return refs


def valid_file_ref(ref):
    return (
        isinstance(ref, dict)
        and isinstance(ref.get("file"), str)
        and isinstance(ref.get("sha256_10"), str)
        and bool(re.fullmatch(r"[0-9a-f]{10}", ref["sha256_10"]))
        and isinstance(ref.get("bytes"), int)
    )


def strength_ref(manifest):
    disciplines = manifest.get("disciplines") if isinstance(manifest, dict) else None
    if not isinstance(disciplines, list):
        return None
    return next(
        (d for d in disciplines if isinstance(d, dict) and d.get("slug") == "strength"),
        None,
    )


def taxonomy_ref(manifest):
    taxonomy = manifest.get("taxonomy") if isinstance(manifest, dict) else None
    return taxonomy if valid_file_ref(taxonomy) else None


def validate_dist_files(manifest, errors):
    refs = manifest_file_refs(manifest)
    if not refs:
        return
    expected = {"manifest.json", *(ref["file"] for ref in refs)}
    try:
        actual = {name for name in os.listdir(DIST_DIR) if name.endswith(".json")}
    except OSError as e:
        errors.append(f"dist directory could not be read: {e}")
        return
    require(
        actual == expected,
        errors,
        f"dist files mismatch: expected={sorted(expected)} actual={sorted(actual)}",
    )
    for ref in refs:
        path = os.path.join(DIST_DIR, ref["file"])
        if not os.path.exists(path):
            errors.append(f"dist file missing: {ref['file']}")
            continue
        require(os.path.getsize(path) == ref["bytes"], errors, f"{ref['file']} byte count mismatch")
        require(sha256_10(path) == ref["sha256_10"], errors, f"{ref['file']} sha mismatch")


def main():
    errors = []
    dist_manifest = load_required_json(
        os.path.join(DIST_DIR, "manifest.json"), errors, "dist manifest"
    )
    app_manifest = load_required_json(
        os.path.join(APP_RESOURCES_DIR, "manifest.json"), errors, "app manifest"
    )
    app_taxonomy = load_required_json(
        os.path.join(APP_RESOURCES_DIR, "taxonomy.json"), errors, "app taxonomy"
    )
    app_strength = load_required_json(
        os.path.join(APP_RESOURCES_DIR, "strength.json"), errors, "app strength catalog"
    )

    require(dist_manifest == app_manifest, errors, "app manifest must match dist manifest")
    validate_manifest(dist_manifest, errors)
    validate_taxonomy(app_taxonomy, errors)
    validate_workouts(app_strength, app_taxonomy, errors)
    validate_dist_files(dist_manifest, errors)

    catalog_ref = strength_ref(dist_manifest)
    if valid_file_ref(catalog_ref) and isinstance(app_strength, list):
        dist_strength = load_required_json(
            os.path.join(DIST_DIR, catalog_ref["file"]), errors, "dist strength catalog"
        )
        require(
            dist_strength == app_strength,
            errors,
            "app strength.json must match dist strength payload",
        )
        require(
            catalog_ref.get("count") == len(app_strength),
            errors,
            "manifest strength count mismatch",
        )
    tax_ref = taxonomy_ref(dist_manifest)
    if tax_ref and isinstance(app_taxonomy, dict):
        dist_taxonomy = load_required_json(
            os.path.join(DIST_DIR, tax_ref["file"]), errors, "dist taxonomy"
        )
        require(
            dist_taxonomy == app_taxonomy,
            errors,
            "app taxonomy.json must match dist taxonomy payload",
        )

    if errors:
        print("JSON CONTRACT: FAIL")
        for error in errors[:40]:
            print(f"  - {error}")
        if len(errors) > 40:
            print(f"  ... {len(errors) - 40} more")
        sys.exit(1)

    print(f"JSON CONTRACT: PASS ({len(app_strength)} strength workouts)")


if __name__ == "__main__":
    main()
