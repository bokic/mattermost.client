#!/bin/bash

# Lints all Swift source files across the application, tests, and tooling using swift-format.
# Optionally invokes SwiftLint if installed for rules that swift-format does not check.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

TARGETS=(
    "$ROOT/mattermost.client"
    "$ROOT/mattermost.clientTests"
    "$ROOT/tools"
)

MODE="lint"
if [ "${1:-}" = "--format" ] || [ "${1:-}" = "--fix" ]; then
    MODE="format"
fi

if [ "$MODE" = "format" ]; then
    echo "Formatting Swift sources with swift-format..."
    xcrun swift-format format -i --parallel --recursive --configuration "$ROOT/.swift-format" "${TARGETS[@]}"
    if command -v swiftlint >/dev/null 2>&1; then
        echo "Running swiftlint autocorrect..."
        swiftlint --fix --quiet || true
    fi
    echo "Formatting complete."
else
    echo "Linting Swift sources with swift-format (--strict)..."
    xcrun swift-format lint --strict --parallel --recursive --configuration "$ROOT/.swift-format" "${TARGETS[@]}"
    if command -v swiftlint >/dev/null 2>&1; then
        echo "Linting Swift sources with SwiftLint..."
        swiftlint lint --strict --quiet
    fi
    echo "Lint passed cleanly."
fi
