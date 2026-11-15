//
//  DesignTokens.swift
//  mattermost.client
//
//  Shared visual tokens for metrics that are repeated across the AppKit views.
//  Colors sourced from the server theme live in `Theme.swift`; this file covers
//  geometry plus the small palette of UI accents that are not user-themed.
//

import AppKit

/// Corner radii used by the workspace chrome.
enum MMRadius {
    /// Small chips and attachment glyphs.
    static let tiny: CGFloat = 3
    /// Buttons, rows and inputs.
    static let control: CGFloat = 4
    /// Menus and small popovers.
    static let menu: CGFloat = 6
    /// Nested panels and elevated cards.
    static let panel: CGFloat = 8
    /// Larger elevated cards and pickers.
    static let card: CGFloat = 10
    /// Main sidebar and channel panels.
    static let window: CGFloat = 12
    /// Large cards such as the emoji picker shell.
    static let large: CGFloat = 14
}

/// Layout metrics that mirror the Mattermost web client at >=1201px.
enum MMMetric {
    static let sidebarWidth: CGFloat = 264
    static let sidebarLeading: CGFloat = 1
    /// The web client keeps a 5pt window margin and a 4pt gutter.
    static let panelGutter: CGFloat = 4
    static let chatPanelLeading: CGFloat = 269
    static let topBarHeight: CGFloat = 44

    static let composerHeight: CGFloat = 50
    static let composerToolbarHeight: CGFloat = 90
    static let composerAttachmentsHeight: CGFloat = 36

    static let rightPanelDefaultWidth: CGFloat = 400
    static let rightPanelMinWidth: CGFloat = 280
    static let searchPopoverWidth: CGFloat = 400
}

/// Accent colors used by native chrome that are not part of the server theme.
@MainActor
enum MMPalette {
    /// Default avatar tint used when a user has no profile image and before the
    /// deterministic palette is applied.
    static let avatarYellow = NSColor(red: 224 / 255, green: 208 / 255, blue: 71 / 255, alpha: 1.0)

    /// Deterministic avatar colors for users without a profile image.
    static var avatarColors: [NSColor] {
        [
            avatarYellow,
            Theme.shared.buttonBg,
            NSColor(red: 139 / 255, green: 92 / 255, blue: 246 / 255, alpha: 1.0),
            NSColor(red: 236 / 255, green: 72 / 255, blue: 153 / 255, alpha: 1.0),
            NSColor(red: 16 / 255, green: 185 / 255, blue: 129 / 255, alpha: 1.0),
            NSColor(red: 245 / 255, green: 158 / 255, blue: 11 / 255, alpha: 1.0)
        ]
    }

    /// "New Messages" divider text and its 50%-opacity rule.
    static let newMessages = NSColor(red: 1.0, green: 136 / 255, blue: 0, alpha: 1.0)
    static let newMessagesLine = NSColor(red: 1.0, green: 136 / 255, blue: 0, alpha: 0.5)

    /// Transient zoom-percentage pill.
    static let zoomHUDBackground = NSColor(red: 27 / 255, green: 29 / 255, blue: 34 / 255, alpha: 0.88)

    /// Lightbox zoom bar chrome over the black backdrop.
    static let lightboxChrome = NSColor(red: 61 / 255, green: 60 / 255, blue: 64 / 255, alpha: 0.75)

    /// Light popup used by the team switcher.
    static let popupBorder = NSColor(white: 0.85, alpha: 1.0)
    static let popupText = NSColor(white: 0.15, alpha: 1.0)
    static let popupSecondaryText = NSColor(white: 0.5, alpha: 1.0)
    static let popupHover = NSColor(white: 0.94, alpha: 1.0)
    static let popupCheck = NSColor(srgbRed: 0.11, green: 0.35, blue: 0.85, alpha: 1.0)
}
