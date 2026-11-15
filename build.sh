#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

LOG_FILE="${TMPDIR:-/tmp}/mattermost-build.log"

echo "Building mattermost.client..."
set +e
xcodebuild -project mattermost.client.xcodeproj -scheme mattermost.client -derivedDataPath build build 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}
set -e

if [ "$STATUS" -ne 0 ]; then
    # Surface compiler diagnostics as GitHub annotations so the exact file,
    # line and message are visible on the run summary without downloading logs.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^(.+\.swift):([0-9]+):([0-9]+):\ error:\ (.*)$ ]]; then
                echo "::error file=${BASH_REMATCH[1]},line=${BASH_REMATCH[2]},col=${BASH_REMATCH[3]}::${BASH_REMATCH[4]}"
            elif [[ "$line" == *"error:"* ]]; then
                echo "::error::$line"
            fi
        done < <(grep -E "error:" "$LOG_FILE" | head -100)
    fi
    echo "Build failed (exit $STATUS). Full log: $LOG_FILE"
    exit "$STATUS"
fi

echo "Build succeeded!"
