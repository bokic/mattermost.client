#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

APP_PATH="build/Build/Products/Release/mattermost.client.app"

APP_VERSION="$("$(dirname "$0")/version.sh" --full)"
DMG_PATH="build/Build/Products/Release/mattermost.client-${APP_VERSION}.dmg"

echo "Building mattermost.client ${APP_VERSION} (Release)..."
xcodebuild -project mattermost.client.xcodeproj -scheme mattermost.client -derivedDataPath build \
    -configuration Release MARKETING_VERSION="$APP_VERSION" build

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
