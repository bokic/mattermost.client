#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Building mattermost.client..."
xcodebuild -project mattermost.client.xcodeproj -scheme mattermost.client -derivedDataPath build build

echo "Build succeeded!"
