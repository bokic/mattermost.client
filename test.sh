#!/bin/bash

set -euo pipefail

LOG_FILE="${TMPDIR:-/tmp}/mattermost-tests.log"

write_diagnostics() {
    local status=$1

    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "## mattermost.client tests failed (exit $status)"
            echo
            echo '```text'
            if ! grep -E "error:|failed|FAIL|Assertion|Test Suite|Executed|error:" "$LOG_FILE" | tail -160; then
                tail -160 "$LOG_FILE"
            fi
            echo '```'
        } >> "$GITHUB_STEP_SUMMARY"
    fi

    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^(.+\.swift):([0-9]+):([0-9]+):\ error:\ (.*)$ ]]; then
                path="${BASH_REMATCH[1]}"
                if [ -n "${GITHUB_WORKSPACE:-}" ]; then
                    path="${path#${GITHUB_WORKSPACE}/}"
                fi
                echo "::error file=${path},line=${BASH_REMATCH[2]},col=${BASH_REMATCH[3]}::${BASH_REMATCH[4]}"
            elif [[ "$line" == *"error:"* || "$line" == *"failed"* ]]; then
                echo "::error::$line"
            fi
        done < <(grep -E "error:|failed|Assertion" "$LOG_FILE" | head -100)
    fi
}

echo "Building and running mattermost.clientTests..."
set +e
# Build for the host architecture so the test target matches the app module
# produced by build.sh (the app scheme uses the active arch only).
xcodebuild -project mattermost.client.xcodeproj \
    -target mattermost.clientTests \
    -configuration Debug \
    ARCHS="$(uname -m)" \
    ONLY_ACTIVE_ARCH=YES \
    SYMROOT="$(pwd)/build/Build/Products" \
    OBJROOT="$(pwd)/build/Build/Intermediates.noindex" \
    build 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}

if [ "$STATUS" -eq 0 ]; then
    xcrun xctest build/Build/Products/Debug/mattermost.clientTests.xctest 2>&1 | tee -a "$LOG_FILE"
    STATUS=${PIPESTATUS[0]}
fi
set -e

if [ "$STATUS" -ne 0 ]; then
    write_diagnostics "$STATUS"
    echo "Tests failed (exit $STATUS). Full log: $LOG_FILE"
    exit "$STATUS"
fi

echo "All unit tests passed!"
