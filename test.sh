#!/bin/bash

set -euo pipefail

LOG_FILE="${TMPDIR:-/tmp}/mattermost-tests.log"
RESULT_BUNDLE="$(pwd)/build/TestResults.xcresult"
COVERAGE_MIN_PERCENT="${COVERAGE_MIN_PERCENT:-50}"

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

echo "Running mattermost.clientTests (hosted in mattermost.client.app)..."
set +e
: > "$LOG_FILE"
rm -rf "$RESULT_BUNDLE"
run_with_timeout 900 xcodebuild -project mattermost.client.xcodeproj \
    -scheme mattermost.client \
    -configuration Debug \
    -derivedDataPath build \
    -destination "platform=macOS" \
    -enableCodeCoverage YES \
    -resultBundlePath "$RESULT_BUNDLE" \
    test >> "$LOG_FILE" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    write_diagnostics "$STATUS"
    echo "Tests failed (exit $STATUS). Full log: $LOG_FILE"
    tail -80 "$LOG_FILE"
    exit "$STATUS"
fi

grep -E "Test Suite 'All tests'|Executed [0-9]+ tests" "$LOG_FILE" | tail -4

if [ ! -d "$RESULT_BUNDLE" ]; then
    echo "Test result bundle not found at $RESULT_BUNDLE"
    exit 1
fi

COVERAGE_JSON="$(xcrun xccov view --report --json "$RESULT_BUNDLE")"
COVERAGE_PERCENT="$(printf '%s' "$COVERAGE_JSON" | python3 -c 'import json,sys; print("%.2f" % (json.load(sys.stdin)["lineCoverage"] * 100))')"
echo "Line coverage: ${COVERAGE_PERCENT}% (minimum ${COVERAGE_MIN_PERCENT}%)"

if python3 -c "import sys; sys.exit(0 if float('${COVERAGE_PERCENT}') >= float('${COVERAGE_MIN_PERCENT}') else 1)"; then
    echo "All unit tests passed!"
else
    echo "Coverage ${COVERAGE_PERCENT}% is below the ${COVERAGE_MIN_PERCENT}% gate."
    exit 1
fi
