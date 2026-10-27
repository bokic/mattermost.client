#!/bin/bash

set -e

echo "Building and running mattermost.clientTests..."
xcodebuild -project mattermost.client.xcodeproj \
    -target mattermost.clientTests \
    -configuration Debug \
    SYMROOT="$(pwd)/build/Build/Products" \
    OBJROOT="$(pwd)/build/Build/Intermediates.noindex" \
    build

xcrun xctest build/Build/Products/Debug/mattermost.clientTests.xctest
echo "All unit tests passed!"
