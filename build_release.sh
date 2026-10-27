#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

APP_PATH="build/Build/Products/Release/mattermost.client.app"

GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
GIT_COMMITS=$(git rev-list "${GIT_TAG}"..HEAD --count 2>/dev/null || echo "0")
DMG_PATH="build/Build/Products/Release/mattermost.client-${GIT_TAG}-${GIT_COMMITS}.dmg"

echo "Building mattermost.client (Release)..."
xcodebuild -project mattermost.client.xcodeproj -scheme mattermost.client -derivedDataPath build -configuration Release build

if [ ! -d "$APP_PATH" ]; then
    echo "Error: .app bundle not found at $APP_PATH"
    exit 1
fi

echo "Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "mattermost.client" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

echo ""
echo "Build succeeded!"
echo "  DMG: $DMG_PATH"
