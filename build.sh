#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

LOG_FILE="${TMPDIR:-/tmp}/mattermost-build.log"
APP_VERSION="$("$(dirname "$0")/version.sh" --full)"

echo "Building mattermost.client $APP_VERSION..."
set +e
xcodebuild -project mattermost.client.xcodeproj -scheme mattermost.client -derivedDataPath build \
    MARKETING_VERSION="$APP_VERSION" build 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}
set -e

if [ "$STATUS" -ne 0 ]; then
    # Put the relevant diagnostics in the run summary as well as in annotations.
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "## mattermost.client build failed (exit $STATUS)"
            echo
            echo '```text'
            if ! grep -E "error:|The following build commands failed|Command .* failed" "$LOG_FILE" | head -120; then
                tail -120 "$LOG_FILE"
            fi
            echo '```'
        } >> "$GITHUB_STEP_SUMMARY"
    fi

    # Surface compiler diagnostics as GitHub annotations so the exact file,
    # line and message are visible on the run summary without downloading logs.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^(.+\.swift):([0-9]+):([0-9]+):\ error:\ (.*)$ ]]; then
                path="${BASH_REMATCH[1]}"
                if [ -n "${GITHUB_WORKSPACE:-}" ]; then
                    path="${path#${GITHUB_WORKSPACE}/}"
                fi
                echo "::error file=${path},line=${BASH_REMATCH[2]},col=${BASH_REMATCH[3]}::${BASH_REMATCH[4]}"
            elif [[ "$line" == *"error:"* ]]; then
                echo "::error::$line"
            fi
        done < <(grep -E "error:" "$LOG_FILE" | head -100)
    fi
    echo "Build failed (exit $STATUS). Full log: $LOG_FILE"
    exit "$STATUS"
fi

echo "Build succeeded!"
