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

run_with_timeout() {
    local limit=$1
    shift
    "$@" &
    local pid=$!
    (
        sleep "$limit"
        # Kill children first; otherwise they can keep a pipe/log handle open and
        # outlive the parent that the watchdog signalled.
        pkill -TERM -P "$pid" 2>/dev/null
        kill -TERM "$pid" 2>/dev/null
        sleep 5
        pkill -KILL -P "$pid" 2>/dev/null
        kill -KILL "$pid" 2>/dev/null
    ) &
    local watchdog=$!
    wait "$pid"
    local status=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    return "$status"
}

echo "Building and running mattermost.clientTests..."
set +e
: > "$LOG_FILE"
echo "=== xcodebuild ===" >> "$LOG_FILE"
# Build for the host architecture so the test target matches the app module
# produced by build.sh (the app scheme uses the active arch only).
run_with_timeout 600 xcodebuild -project mattermost.client.xcodeproj \
    -target mattermost.clientTests \
    -configuration Debug \
    ARCHS="$(uname -m)" \
    ONLY_ACTIVE_ARCH=YES \
    SYMROOT="$(pwd)/build/Build/Products" \
    OBJROOT="$(pwd)/build/Build/Intermediates.noindex" \
    build >> "$LOG_FILE" 2>&1
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
    echo "=== xctest ===" >> "$LOG_FILE"
    run_with_timeout 180 xcrun xctest build/Build/Products/Debug/mattermost.clientTests.xctest >> "$LOG_FILE" 2>&1
    STATUS=$?
fi
set -e

if [ "$STATUS" -ne 0 ]; then
    write_diagnostics "$STATUS"
    echo "Tests failed (exit $STATUS). Full log: $LOG_FILE"
    tail -80 "$LOG_FILE"
    exit "$STATUS"
fi

grep -E "Test Suite 'All tests'|Executed [0-9]+ tests" "$LOG_FILE" | tail -4
echo "All unit tests passed!"
