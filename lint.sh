#!/bin/bash

# Lints files that have been migrated to swift-format. The legacy UI files still
# carry historical formatting, so add them here as they are cleaned up rather
# than reformatting the whole repository at once.

set -e

FILES=(
    mattermost.client/ChatViewModel.swift
    mattermost.client/DesignTokens.swift
    mattermost.client/TimelineSupport.swift
    mattermost.client/WindowZoomController.swift
    mattermost.client/ZoomManager.swift
    mattermost.client/ZoomHUD.swift
    mattermost.clientTests/APIClientTests.swift
    mattermost.clientTests/ChatViewModelTests.swift
    mattermost.clientTests/DebugLogTests.swift
    mattermost.clientTests/FileTransferTests.swift
    mattermost.clientTests/KeychainHelperTests.swift
    mattermost.clientTests/ThemeTests.swift
    mattermost.clientTests/TimelineSupportTests.swift
    mattermost.clientTests/WebServiceErrorTests.swift
    mattermost.clientTests/WebServiceTests.swift
    mattermost.clientTests/WebSocketClientTests.swift
    mattermost.clientTests/ZoomTests.swift
    tools/hud_measure.swift
)

exec xcrun swift-format lint --strict --configuration .swift-format "${FILES[@]}"
