#!/bin/bash

APP_BUNDLE="build/Build/Products/Debug/mattermost.client.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/mattermost.client"

if [ -f "$APP_BINARY" ]; then
    echo "Starting mattermost.client..."
    open -W "$APP_BUNDLE"
else
    echo "Error: Application binary not found."
    echo "Please run ./build.sh first to build the application."
    exit 1
fi
