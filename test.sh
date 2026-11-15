#!/bin/bash

set -e

echo "Building and running mattermost.clientTests..."
# Build for the host architecture so the test target matches the app module
# produced by build.sh (the app scheme uses the active arch only).
xcodebuild -project mattermost.client.xcodeproj \
    -target mattermost.clientTests \
    -configuration Debug \
    ARCHS="$(uname -m)" \
    ONLY_ACTIVE_ARCH=YES \
    SYMROOT="$(pwd)/build/Build/Products" \
    OBJROOT="$(pwd)/build/Build/Intermediates.noindex" \
    build

xcrun xctest build/Build/Products/Debug/mattermost.clientTests.xctest
echo "All unit tests passed!"
