#!/usr/bin/env bash
# List active (non-expired) TestFlight builds and expire one or more of them,
# using the App Store Connect API directly (curl + openssl + python3 stdlib +
# jq — no fastlane/gems required). Auth comes from the same API_KEY_ID /
# API_ISSUER_ID / API_KEY_PATH used by `make upload` in the repo-root .env.
#
# Usage:
#   scripts/expire-testflight-build.sh                 interactive: list active builds, pick which to expire
#   scripts/expire-testflight-build.sh list             just list active builds, no prompt
#   scripts/expire-testflight-build.sh <build-number>   expire that build number directly, no prompt
#
# Optional: BUNDLE_ID env var overrides the default (sh.saad.grypd).

set -euo pipefail

for tool in curl jq openssl python3; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "❌ '$tool' is required but not found on PATH (e.g. \`brew install $tool\`)." >&2
    exit 1
  fi
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -f .env ]; then
  echo "❌ No .env file found. Copy .env.example to .env and fill in your App Store Connect API key." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${API_KEY_ID:?Set API_KEY_ID in .env}"
: "${API_ISSUER_ID:?Set API_ISSUER_ID in .env}"
: "${API_KEY_PATH:?Set API_KEY_PATH in .env}"

BUNDLE_ID="${BUNDLE_ID:-sh.saad.grypd}"
API="https://api.appstoreconnect.apple.com/v1"
JWT="$(python3 "$ROOT/scripts/lib/mint_jwt.py" "$API_KEY_ID" "$API_ISSUER_ID" "$API_KEY_PATH")"

# Auth header is passed to curl via a stdin config file (`-K -`) rather than
# `-H` on the command line, so the bearer token never appears in argv (and
# therefore never shows up to other local users via `ps`).
api_request() {
  # $2 may be a path (prefixed with $API) or a full URL (used as-is, e.g.
  # when following a `links.next` pagination cursor).
  local method="$1" path="$2" data="${3:-}" context="$4"
  local url response status body curl_args=(-sS -g -K - -X "$method" -w '\n%{http_code}')
  [[ "$path" == http* ]] && url="$path" || url="$API$path"
  if [ -n "$data" ]; then
    curl_args+=(-H "Content-Type: application/json" -d "$data")
  fi
  response="$(curl "${curl_args[@]}" "$url" <<< "header = \"Authorization: Bearer $JWT\"")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "❌ $context failed (HTTP $status):" >&2
    if echo "$body" | jq -e '.errors' > /dev/null 2>&1; then
      echo "$body" | jq -r '.errors[] | "  \(.title): \(.detail // "")"' >&2
    else
      echo "  $body" >&2
    fi
    exit 1
  fi
  echo "$body"
}

api_get() {
  api_request GET "$1" "" "$2"
}

api_patch_expire() {
  api_request PATCH "/builds/$1" "{\"data\":{\"type\":\"builds\",\"id\":\"$1\",\"attributes\":{\"expired\":true}}}" "Expiring build (id $1)"
}

APP_JSON="$(api_get "/apps?filter[bundleId]=$BUNDLE_ID&fields[apps]=bundleId" "Looking up app $BUNDLE_ID")"
APP_ID="$(echo "$APP_JSON" | jq -r '.data[0].id // empty')"
if [ -z "$APP_ID" ]; then
  echo "❌ No app found for bundle id $BUNDLE_ID" >&2
  exit 1
fi

# Fetches every page of active builds (following `links.next`) and merges
# them into a single {data, included} object, so `all` and the listing can't
# silently miss builds beyond the first 200.
fetch_active_builds() {
  local url="/builds?filter[app]=$APP_ID&filter[expired]=false&include=preReleaseVersion&fields[builds]=version,uploadedDate,processingState,expired,preReleaseVersion&fields[preReleaseVersions]=version,platform&sort=-uploadedDate&limit=200"
  local page merged='{"data":[],"included":[]}'
  while [ -n "$url" ]; do
    page="$(api_get "$url" "Listing active builds")"
    merged="$(jq -n --argjson a "$merged" --argjson b "$page" \
      '{data: ($a.data + $b.data), included: (($a.included // []) + ($b.included // []))}')"
    url="$(echo "$page" | jq -r '.links.next // empty')"
  done
  echo "$merged"
}

print_table() {
  local builds_json="$1"
  echo "$builds_json" | jq -r '
    (.included // []) as $inc
    | .data
    | to_entries[]
    | . as $e
    | ($e.value) as $b
    | ($inc[] | select(.id == $b.relationships.preReleaseVersion.data.id)) as $prv
    | [ ($e.key + 1 | tostring), $prv.attributes.version, $b.attributes.version, $prv.attributes.platform, $b.attributes.processingState, $b.attributes.uploadedDate ]
    | @tsv
  ' | awk -F'\t' 'BEGIN { printf "%-4s %-12s %-8s %-8s %-12s %s\n", "#", "VERSION", "BUILD", "PLATFORM", "STATE", "UPLOADED" }
       { printf "%-4s %-12s %-8s %-8s %-12s %s\n", $1, $2, $3, $4, $5, $6 }'
}

expire_build_id() {
  local build_id="$1" label="$2"
  local resp
  resp="$(api_patch_expire "$build_id")"
  if [ "$(echo "$resp" | jq -r '.data.attributes.expired')" == "true" ]; then
    echo "✅ Expired $label"
  else
    echo "❌ Failed to expire $label (unexpected response)" >&2
    exit 1
  fi
}

if [ $# -gt 1 ]; then
  echo "Usage: $0 [list|<build-number>]" >&2
  exit 1
fi

MODE="${1:-}"

if [ -n "$MODE" ] && [ "$MODE" != "list" ] && ! [[ "$MODE" =~ ^[0-9]+$ ]]; then
  echo "❌ Unknown argument: $MODE" >&2
  echo "Usage: $0 [list|<build-number>]" >&2
  exit 1
fi

if [[ "$MODE" =~ ^[0-9]+$ ]]; then
  # Direct mode: expire a specific build number without prompting. Build
  # numbers aren't guaranteed unique across marketing versions, so fetch
  # preReleaseVersion too and refuse to guess if more than one build matches.
  BUILD_JSON="$(api_get "/builds?filter[app]=$APP_ID&filter[version]=$MODE&include=preReleaseVersion&fields[builds]=version,expired,preReleaseVersion&fields[preReleaseVersions]=version" "Looking up build $MODE")"
  MATCH_COUNT="$(echo "$BUILD_JSON" | jq '.data | length')"
  if [ "$MATCH_COUNT" -eq 0 ]; then
    echo "❌ No build found with build number $MODE for $BUNDLE_ID" >&2
    exit 1
  fi
  if [ "$MATCH_COUNT" -gt 1 ]; then
    echo "❌ Build number $MODE is ambiguous — $MATCH_COUNT builds match it across different marketing versions:" >&2
    echo "$BUILD_JSON" | jq -r '
      (.included // []) as $inc
      | .data[]
      | . as $b
      | ($inc[] | select(.id == $b.relationships.preReleaseVersion.data.id)) as $prv
      | "  version \($prv.attributes.version), build \($b.attributes.version), expired=\($b.attributes.expired)"
    ' >&2
    echo "Use interactive mode (no arguments) to pick the exact one." >&2
    exit 1
  fi
  BUILD_ID="$(echo "$BUILD_JSON" | jq -r '.data[0].id')"
  if [ "$(echo "$BUILD_JSON" | jq -r '.data[0].attributes.expired')" == "true" ]; then
    echo "ℹ️  Build $MODE is already expired."
    exit 0
  fi
  expire_build_id "$BUILD_ID" "build $MODE"
  exit 0
fi

BUILDS_JSON="$(fetch_active_builds)"

COUNT="$(echo "$BUILDS_JSON" | jq '.data | length')"
if [ "$COUNT" -eq 0 ]; then
  echo "No active (non-expired) builds found for $BUNDLE_ID."
  exit 0
fi

echo "Active TestFlight builds for $BUNDLE_ID:"
print_table "$BUILDS_JSON"

if [ "$MODE" == "list" ]; then
  exit 0
fi

echo
read -r -p "Expire which? (comma-separated #s, 'all', or blank to cancel): " SELECTION
SELECTION="$(echo "$SELECTION" | xargs)"

if [ -z "$SELECTION" ]; then
  echo "Cancelled."
  exit 0
fi

if [ "$SELECTION" == "all" ]; then
  INDICES="$(seq 1 "$COUNT")"
else
  INDICES="$(echo "$SELECTION" | tr ',' '\n' | xargs -n1)"
fi

# One-time index -> "buildId<TAB>marketingVersion<TAB>buildNumber" lookup table.
ROWS="$(echo "$BUILDS_JSON" | jq -r '
  (.included // []) as $inc
  | .data
  | to_entries[]
  | . as $e
  | ($inc[] | select(.id == $e.value.relationships.preReleaseVersion.data.id)) as $prv
  | [($e.key + 1 | tostring), $e.value.id, $prv.attributes.version, $e.value.attributes.version] | @tsv
')"

EXPIRED_COUNT=0
for i in $INDICES; do
  if ! [[ "$i" =~ ^[0-9]+$ ]] || [ "$i" -lt 1 ] || [ "$i" -gt "$COUNT" ]; then
    echo "⚠️  Skipping invalid selection: $i" >&2
    continue
  fi
  ROW="$(echo "$ROWS" | awk -F'\t' -v i="$i" '$1 == i')"
  BUILD_ID="$(echo "$ROW" | cut -f2)"
  VERSION="$(echo "$ROW" | cut -f3)"
  BUILD_NUM="$(echo "$ROW" | cut -f4)"
  expire_build_id "$BUILD_ID" "$VERSION ($BUILD_NUM)"
  EXPIRED_COUNT=$((EXPIRED_COUNT + 1))
done

if [ "$EXPIRED_COUNT" -eq 0 ]; then
  echo "⚠️  No valid builds selected — nothing expired." >&2
  exit 1
fi
