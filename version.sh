#!/bin/bash

# Prints the build version derived from the nearest local tag plus the number of
# commits since that tag: "<tag>.<commits>". When HEAD is exactly on the tag no
# suffix is added. Tags are intentionally not required to be pushed; if none
# exist we fall back to MARKETING_VERSION in the project.
#
# Usage: ./version.sh [--base|--count|--full]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MODE="${1:---full}"

BASE="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [ -n "$BASE" ] && git rev-parse -q --verify "refs/tags/${BASE}" >/dev/null 2>&1; then
    COUNT="$(git rev-list "${BASE}"..HEAD --count 2>/dev/null || echo 0)"
else
    BASE="$(
        sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' mattermost.client.xcodeproj/project.pbxproj |
            head -1
    )"
    [ -n "$BASE" ] || BASE="0.0.0"
    COUNT=0
fi

if [ "$COUNT" -eq 0 ]; then
    FULL="$BASE"
else
    FULL="${BASE}.${COUNT}"
fi

case "$MODE" in
    --base) echo "$BASE" ;;
    --count) echo "$COUNT" ;;
    --full | "") echo "$FULL" ;;
    *)
        echo "usage: $0 [--base|--count|--full]" >&2
        exit 2
        ;;
esac
