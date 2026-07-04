#!/usr/bin/env python3
"""One-command catalog build from a SeaTable .dtable export."""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

from common import APP_RESOURCES_DIR, DIST_DIR, ROOT, SCRATCH_DIR, load_json, write_json


def run(cmd, *, env=None):
    print("→", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=ROOT, check=True, env=env)


def unpack_dtable(path):
    if not os.path.isfile(path):
        raise SystemExit(f".dtable export not found: {path}")
    if not zipfile.is_zipfile(path):
        raise SystemExit(f"not a valid .dtable zip archive: {path}")

    shutil.rmtree(SCRATCH_DIR, ignore_errors=True)
    os.makedirs(SCRATCH_DIR, exist_ok=True)
    with zipfile.ZipFile(path) as zf:
        for name in ("content.json", "forms.json"):
            try:
                zf.extract(name, SCRATCH_DIR)
            except KeyError:
                if name == "content.json":
                    raise SystemExit(f"export did not contain content.json: {path}") from None

    content = os.path.join(SCRATCH_DIR, "content.json")
    if not os.path.isfile(content):
        raise SystemExit(f"export did not contain scratch_dtable/content.json: {path}")
    print(f"→ Unpacked {os.path.relpath(path, ROOT)} into scratch_dtable/")


def load_manifest(dist_dir):
    return load_json(os.path.join(dist_dir, "manifest.json"))


def sync_app_resources(manifest, *, dist_dir, app_resources_dir):
    os.makedirs(app_resources_dir, exist_ok=True)

    shutil.copyfile(
        os.path.join(dist_dir, "manifest.json"),
        os.path.join(app_resources_dir, "manifest.json"),
    )

    taxonomy_file = manifest["taxonomy"]["file"]
    sync_pretty_json(
        os.path.join(dist_dir, taxonomy_file),
        os.path.join(app_resources_dir, "taxonomy.json"),
    )

    for discipline in manifest["disciplines"]:
        if discipline["slug"] != "strength":
            continue
        sync_pretty_json(
            os.path.join(dist_dir, discipline["file"]),
            os.path.join(app_resources_dir, "strength.json"),
        )
        break
    else:
        raise SystemExit("manifest does not contain the strength discipline")

    print("→ Synced app/GRYPD/Resources/{manifest,strength,taxonomy}.json")


def sync_pretty_json(src, dst):
    write_json(dst, load_json(src), indent=1)


def prune_dist(manifest, *, dist_dir):
    keep = {
        "manifest.json",
        manifest["taxonomy"]["file"],
        *(discipline["file"] for discipline in manifest["disciplines"]),
    }
    removed = []
    for name in os.listdir(dist_dir):
        path = os.path.join(dist_dir, name)
        if os.path.isfile(path) and name.endswith(".json") and name not in keep:
            os.remove(path)
            removed.append(name)

    if removed:
        print("→ Pruned stale dist files:")
        for name in sorted(removed):
            print(f"  {name}")
    else:
        print("→ No stale dist files to prune")


def verify_dist(manifest, *, dist_dir):
    expected = [
        "manifest.json",
        manifest["taxonomy"]["file"],
        *(discipline["file"] for discipline in manifest["disciplines"]),
    ]
    missing = [name for name in expected if not os.path.isfile(os.path.join(dist_dir, name))]
    extra = [
        name for name in os.listdir(dist_dir) if name.endswith(".json") and name not in expected
    ]
    if missing or extra:
        raise SystemExit(
            f"dist verification failed; missing={missing or 'none'} extra={extra or 'none'}"
        )

    strength = next(d for d in manifest["disciplines"] if d["slug"] == "strength")
    print(
        f"→ Verified dist: {strength['count']} strength workouts, "
        f"{strength['file']}, {manifest['taxonomy']['file']}"
    )


def write_pages_headers(manifest, *, dist_dir):
    immutable_files = [
        manifest["taxonomy"]["file"],
        *(discipline["file"] for discipline in manifest["disciplines"]),
    ]
    headers = """/manifest.json
  Cache-Control: no-cache

"""
    for filename in immutable_files:
        headers += f"/{filename}\n"
        headers += "  Cache-Control: public, max-age=31536000, immutable\n\n"
    headers = headers.rstrip() + "\n"

    with open(os.path.join(dist_dir, "_headers"), "w", encoding="utf-8") as f:
        f.write(headers)
    print("→ Wrote Cloudflare Pages cache headers")


def validation_env(dist_dir, app_resources_dir):
    env = os.environ.copy()
    env["GRYPD_DIST_DIR"] = dist_dir
    env["GRYPD_APP_RESOURCES_DIR"] = app_resources_dir
    return env


def publish_dist(staged_dist):
    backup = None
    parent = os.path.dirname(DIST_DIR)
    os.makedirs(parent, exist_ok=True)
    publish_tmp = tempfile.mkdtemp(prefix=".dist-publish-", dir=parent)
    shutil.rmtree(publish_tmp)
    shutil.copytree(staged_dist, publish_tmp)

    if os.path.exists(DIST_DIR):
        backup = tempfile.mkdtemp(prefix=".dist-backup-", dir=parent)
        shutil.rmtree(backup)
        os.replace(DIST_DIR, backup)
    try:
        os.replace(publish_tmp, DIST_DIR)
    except Exception:
        if backup and not os.path.exists(DIST_DIR):
            os.replace(backup, DIST_DIR)
        raise
    if backup:
        shutil.rmtree(backup, ignore_errors=True)
    print("→ Published staged dist/")


def publish_app_resources(staged_app_resources):
    os.makedirs(APP_RESOURCES_DIR, exist_ok=True)
    for name in ("manifest.json", "strength.json", "taxonomy.json"):
        src = os.path.join(staged_app_resources, name)
        dst = os.path.join(APP_RESOURCES_DIR, name)
        tmp = f"{dst}.tmp"
        shutil.copyfile(src, tmp)
        os.replace(tmp, dst)
    print("→ Published staged app resource snapshot")


def main():
    parser = argparse.ArgumentParser(
        description="Build the GRYPD catalog from a SeaTable .dtable export."
    )
    parser.add_argument(
        "dtable",
        nargs="?",
        default="Weekly Workouts.dtable",
        help="path to the SeaTable .dtable export (default: Weekly Workouts.dtable)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=1000,
        help="maximum linked Apple workouts to enrich this run (default: 1000)",
    )
    args = parser.parse_args()

    dtable_path = args.dtable
    if not os.path.isabs(dtable_path):
        dtable_path = os.path.join(ROOT, dtable_path)

    unpack_dtable(dtable_path)
    run(["python3", "pipeline/enrich.py", str(args.limit)])

    with tempfile.TemporaryDirectory(prefix="grypd-catalog-") as staging_dir:
        staged_dist = os.path.join(staging_dir, "dist")
        staged_app_resources = os.path.join(staging_dir, "app_resources")
        env = validation_env(staged_dist, staged_app_resources)

        run(["python3", "pipeline/assemble.py"], env=env)
        manifest = load_manifest(staged_dist)
        prune_dist(manifest, dist_dir=staged_dist)
        verify_dist(manifest, dist_dir=staged_dist)
        write_pages_headers(manifest, dist_dir=staged_dist)
        sync_app_resources(manifest, dist_dir=staged_dist, app_resources_dir=staged_app_resources)
        run(["python3", "pipeline/validate_outputs.py"], env=env)

        publish_dist(staged_dist)
        publish_app_resources(staged_app_resources)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(e.returncode)
