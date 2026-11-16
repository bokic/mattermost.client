//
//  Theme.swift
//  mattermost.client
//
//  Server-backed Mattermost theme support. The web client stores a theme object in
//  the `theme` preference (per team or globally); this parses the same palette and
//  exposes derived surface/text colors for the native views.
//

import AppKit

@MainActor
enum Theme {
    static var shared: MMTheme { ThemeManager.shared.theme }
}

@MainActor
struct MMTheme {
    let typeName: String
    let isDark: Bool

    let sidebarBg: NSColor
    let sidebarText: NSColor
    let sidebarUnreadText: NSColor
    let sidebarHoverBg: NSColor
    let sidebarActiveBorder: NSColor
    let sidebarActiveColor: NSColor
    let sidebarHeaderBg: NSColor
    let sidebarHeaderText: NSColor
    let sidebarTeamBarBg: NSColor

    let centerBg: NSColor
    let centerText: NSColor
    let linkColor: NSColor
    let buttonBg: NSColor
    let buttonColor: NSColor
    let mentionBg: NSColor
    let mentionColor: NSColor
    let mentionHighlightBg: NSColor
    let mentionHighlightLink: NSColor
    let newMessageSeparator: NSColor
    let errorText: NSColor

    let onlineIndicator: NSColor
    let awayIndicator: NSColor
    let dndIndicator: NSColor

    // MARK: - Derived surfaces

    var centerTextMuted: NSColor {
        centerText.blended(withFraction: isDark ? 0.42 : 0.60, of: centerBg) ?? centerText
    }

    var centerTextPlaceholder: NSColor {
        centerText.blended(withFraction: isDark ? 0.58 : 0.72, of: centerBg) ?? centerTextMuted
    }

    var divider: NSColor {
        centerText.blended(withFraction: isDark ? 0.82 : 0.88, of: centerBg) ?? centerBg
    }

    var centerHover: NSColor {
        centerText.blended(withFraction: isDark ? 0.92 : 0.96, of: centerBg) ?? centerBg
    }

    var centerHoverSubtle: NSColor {
        centerText.blended(withFraction: isDark ? 0.96 : 0.985, of: centerBg) ?? centerBg
    }

    var codeBg: NSColor {
        centerText.blended(withFraction: isDark ? 0.90 : 0.92, of: centerBg) ?? centerBg
    }

    var inputBorder: NSColor {
        centerText.blended(withFraction: isDark ? 0.78 : 0.86, of: centerBg) ?? divider
    }

    var sidebarTextMuted: NSColor {
        sidebarText.blended(withFraction: isDark ? 0.38 : 0.30, of: sidebarBg) ?? sidebarText
    }

    // MARK: - Built-ins

    static let denim = MMTheme(
        typeName: "Denim",
        sidebarBg: "#1e325c",
        sidebarText: "#ffffff",
        sidebarUnreadText: "#ffffff",
        sidebarHoverBg: "#28427b",
        sidebarActiveBorder: "#5d89ea",
        sidebarActiveColor: "#ffffff",
        sidebarHeaderBg: "#192a4d",
        sidebarHeaderTextColor: "#ffffff",
        sidebarTeamBarBg: "#162545",
        centerChannelBg: "#ffffff",
        centerChannelColor: "#3f4350",
        newMessageSeparator: "#cc8f00",
        linkColor: "#386fe5",
        buttonBg: "#1c58d9",
        buttonColor: "#ffffff",
        errorTextColor: "#d24b4e",
        mentionBg: "#ffffff",
        mentionColor: "#1e325c",
        mentionHighlightBg: "#ffd470",
        mentionHighlightLink: "#1b1d22",
        onlineIndicator: "#3db887",
        awayIndicator: "#ffbc1f",
        dndIndicator: "#d24b4e"
    )

    static let indigo = MMTheme(
        typeName: "Indigo",
        sidebarBg: "#151e32",
        sidebarText: "#ffffff",
        sidebarUnreadText: "#ffffff",
        sidebarHoverBg: "#222c3f",
        sidebarActiveBorder: "#4a7ce8",
        sidebarActiveColor: "#ffffff",
        sidebarHeaderBg: "#182339",
        sidebarHeaderTextColor: "#ffffff",
        sidebarTeamBarBg: "#1c2740",
        centerChannelBg: "#111827",
        centerChannelColor: "#dddfe4",
        newMessageSeparator: "#81a3ef",
        linkColor: "#5d89ea",
        buttonBg: "#4a7ce8",
        buttonColor: "#ffffff",
        errorTextColor: "#d24b4e",
        mentionBg: "#4a7ce8",
        mentionColor: "#ffffff",
        mentionHighlightBg: "#133a91",
        mentionHighlightLink: "#a4f4f4",
        onlineIndicator: "#3db887",
        awayIndicator: "#f5ab00",
        dndIndicator: "#d24b4e"
    )

    static let onyx = MMTheme(
        typeName: "Onyx",
        sidebarBg: "#202228",
        sidebarText: "#ffffff",
        sidebarUnreadText: "#ffffff",
        sidebarHoverBg: "#25262a",
        sidebarActiveBorder: "#4a7ce8",
        sidebarActiveColor: "#ffffff",
        sidebarHeaderBg: "#24272d",
        sidebarHeaderTextColor: "#ffffff",
        sidebarTeamBarBg: "#292c33",
        centerChannelBg: "#191b1f",
        centerChannelColor: "#e3e4e8",
        newMessageSeparator: "#1adbdb",
        linkColor: "#5d89ea",
        buttonBg: "#4a7ce8",
        buttonColor: "#ffffff",
        errorTextColor: "#da6c6e",
        mentionBg: "#4b7ce7",
        mentionColor: "#ffffff",
        mentionHighlightBg: "#0d6e6e",
        mentionHighlightLink: "#a4f4f4",
        onlineIndicator: "#3db887",
        awayIndicator: "#f5ab00",
        dndIndicator: "#d24b4e"
    )

    static let quartz = MMTheme(
        typeName: "Quartz",
        sidebarBg: "#f4f4f6",
        sidebarText: "#1f2228",
        sidebarUnreadText: "#1f2228",
        sidebarHoverBg: "#e8eaed",
        sidebarActiveBorder: "#32a4ec",
        sidebarActiveColor: "#1f2228",
        sidebarHeaderBg: "#ebecef",
        sidebarHeaderTextColor: "#1f2228",
        sidebarTeamBarBg: "#e5e7eb",
        centerChannelBg: "#ffffff",
        centerChannelColor: "#3f4350",
        newMessageSeparator: "#15b7b7",
        linkColor: "#1c58d9",
        buttonBg: "#1c58d9",
        buttonColor: "#ffffff",
        errorTextColor: "#d24b4e",
        mentionBg: "#1c58d9",
        mentionColor: "#ffffff",
        mentionHighlightBg: "#7ff0f0",
        mentionHighlightLink: "#0d6e6e",
        onlineIndicator: "#3db887",
        awayIndicator: "#f5ab07",
        dndIndicator: "#d24b4e"
    )

    static let sapphire = MMTheme(
        typeName: "Sapphire",
        sidebarBg: "#1543a3",
        sidebarText: "#ffffff",
        sidebarUnreadText: "#ffffff",
        sidebarHoverBg: "#2a58ba",
        sidebarActiveBorder: "#57b5f0",
        sidebarActiveColor: "#ffffff",
        sidebarHeaderBg: "#123b91",
        sidebarHeaderTextColor: "#ffffff",
        sidebarTeamBarBg: "#123582",
        centerChannelBg: "#ffffff",
        centerChannelColor: "#3f4350",
        newMessageSeparator: "#15b7b7",
        linkColor: "#1c58d9",
        buttonBg: "#1c58d9",
        buttonColor: "#ffffff",
        errorTextColor: "#d24b4e",
        mentionBg: "#ffffff",
        mentionColor: "#174ab5",
        mentionHighlightBg: "#7ff0f0",
        mentionHighlightLink: "#0d6e6e",
        onlineIndicator: "#3db887",
        awayIndicator: "#ffbc1f",
        dndIndicator: "#d24b4e"
    )

    static func builtin(for type: String) -> MMTheme? {
        switch type.lowercased() {
        case "system":
            let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .onyx : .denim
        case "denim", "default", "mattermost": return .denim
        case "indigo": return .indigo
        case "onyx", "dark": return .onyx
        case "quartz": return .quartz
        case "sapphire": return .sapphire
        default: return nil
        }
    }

    // MARK: - Preference parsing

    init(json: [String: Any]) {
        let type = (json["type"] as? String) ?? "custom"
        let isSystemDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fallback = MMTheme.builtin(for: type) ?? (isSystemDark ? .onyx : .denim)
        typeName = type

        func color(_ key: String, _ fallbackColor: NSColor) -> NSColor {
            guard let raw = json[key] as? String else { return fallbackColor }
            return MMTheme.parseColor(raw) ?? fallbackColor
        }

        sidebarBg = color("sidebarBg", fallback.sidebarBg)
        sidebarText = color("sidebarText", fallback.sidebarText)
        sidebarUnreadText = color("sidebarUnreadText", fallback.sidebarUnreadText)
        sidebarHoverBg = color("sidebarTextHoverBg", fallback.sidebarHoverBg)
        sidebarActiveBorder = color("sidebarTextActiveBorder", fallback.sidebarActiveBorder)
        sidebarActiveColor = color("sidebarTextActiveColor", fallback.sidebarActiveColor)
        sidebarHeaderBg = color("sidebarHeaderBg", fallback.sidebarHeaderBg)
        sidebarHeaderText = color("sidebarHeaderTextColor", fallback.sidebarHeaderText)
        sidebarTeamBarBg = color("sidebarTeamBarBg", fallback.sidebarTeamBarBg)

        centerBg = color("centerChannelBg", fallback.centerBg)
        centerText = color("centerChannelColor", fallback.centerText)
        linkColor = color("linkColor", fallback.linkColor)
        buttonBg = color("buttonBg", fallback.buttonBg)
        buttonColor = color("buttonColor", fallback.buttonColor)
        mentionBg = color("mentionBg", fallback.mentionBg)
        mentionColor = color("mentionColor", fallback.mentionColor)
        mentionHighlightBg = color("mentionHighlightBg", fallback.mentionHighlightBg)
        mentionHighlightLink = color("mentionHighlightLink", fallback.mentionHighlightLink)
        newMessageSeparator = color("newMessageSeparator", fallback.newMessageSeparator)
        errorText = color("errorTextColor", fallback.errorText)
        onlineIndicator = color("onlineIndicator", fallback.onlineIndicator)
        awayIndicator = color("awayIndicator", fallback.awayIndicator)
        dndIndicator = color("dndIndicator", fallback.dndIndicator)

        isDark = MMTheme.luminance(of: centerBg) < 0.5
    }

    private init(
        typeName: String,
        sidebarBg: String,
        sidebarText: String,
        sidebarUnreadText: String,
        sidebarHoverBg: String,
        sidebarActiveBorder: String,
        sidebarActiveColor: String,
        sidebarHeaderBg: String,
        sidebarHeaderTextColor: String,
        sidebarTeamBarBg: String,
        centerChannelBg: String,
        centerChannelColor: String,
        newMessageSeparator: String,
        linkColor: String,
        buttonBg: String,
        buttonColor: String,
        errorTextColor: String,
        mentionBg: String,
        mentionColor: String,
        mentionHighlightBg: String,
        mentionHighlightLink: String,
        onlineIndicator: String,
        awayIndicator: String,
        dndIndicator: String
    ) {
        self.typeName = typeName
        self.sidebarBg = MMTheme.parseColor(sidebarBg) ?? .black
        self.sidebarText = MMTheme.parseColor(sidebarText) ?? .white
        self.sidebarUnreadText = MMTheme.parseColor(sidebarUnreadText) ?? .white
        self.sidebarHoverBg = MMTheme.parseColor(sidebarHoverBg) ?? .black
        self.sidebarActiveBorder = MMTheme.parseColor(sidebarActiveBorder) ?? .blue
        self.sidebarActiveColor = MMTheme.parseColor(sidebarActiveColor) ?? .white
        self.sidebarHeaderBg = MMTheme.parseColor(sidebarHeaderBg) ?? .black
        self.sidebarHeaderText = MMTheme.parseColor(sidebarHeaderTextColor) ?? .white
        self.sidebarTeamBarBg = MMTheme.parseColor(sidebarTeamBarBg) ?? .black
        self.centerBg = MMTheme.parseColor(centerChannelBg) ?? .white
        self.centerText = MMTheme.parseColor(centerChannelColor) ?? .black
        self.newMessageSeparator = MMTheme.parseColor(newMessageSeparator) ?? .orange
        self.linkColor = MMTheme.parseColor(linkColor) ?? .blue
        self.buttonBg = MMTheme.parseColor(buttonBg) ?? .blue
        self.buttonColor = MMTheme.parseColor(buttonColor) ?? .white
        self.errorText = MMTheme.parseColor(errorTextColor) ?? .red
        self.mentionBg = MMTheme.parseColor(mentionBg) ?? .blue
        self.mentionColor = MMTheme.parseColor(mentionColor) ?? .white
        self.mentionHighlightBg = MMTheme.parseColor(mentionHighlightBg) ?? .yellow
        self.mentionHighlightLink = MMTheme.parseColor(mentionHighlightLink) ?? .blue
        self.onlineIndicator = MMTheme.parseColor(onlineIndicator) ?? .green
        self.awayIndicator = MMTheme.parseColor(awayIndicator) ?? .orange
        self.dndIndicator = MMTheme.parseColor(dndIndicator) ?? .red
        self.isDark = MMTheme.luminance(of: self.centerBg) < 0.5
    }

    static func parseColor(_ raw: String) -> NSColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Hex formats (#RGB, #RGBA, #RRGGBB, #RRGGBBAA)
        if trimmed.hasPrefix("#") {
            var hex = String(trimmed.dropFirst())
            if hex.count == 3 {
                // #RGB -> #RRGGBB
                hex = hex.map { "\($0)\($0)" }.joined()
            } else if hex.count == 4 {
                // #RGBA -> #RRGGBBAA
                hex = hex.map { "\($0)\($0)" }.joined()
            }
            guard hex.count == 6 || hex.count == 8,
                let value = UInt64(hex, radix: 16)
            else { return nil }
            let red: CGFloat
            let green: CGFloat
            let blue: CGFloat
            let alpha: CGFloat
            if hex.count == 8 {
                red = CGFloat((value >> 24) & 0xFF) / 255
                green = CGFloat((value >> 16) & 0xFF) / 255
                blue = CGFloat((value >> 8) & 0xFF) / 255
                alpha = CGFloat(value & 0xFF) / 255
            } else {
                red = CGFloat((value >> 16) & 0xFF) / 255
                green = CGFloat((value >> 8) & 0xFF) / 255
                blue = CGFloat(value & 0xFF) / 255
                alpha = 1
            }
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }

        // 2. CSS rgb(...) and rgba(...)
        let lower = trimmed.lowercased()
        if (lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(")) && lower.hasSuffix(")") {
            let startIdx = lower.firstIndex(of: "(").map { lower.index(after: $0) } ?? lower.startIndex
            let endIdx = lower.index(before: lower.endIndex)
            let inner = lower[startIdx..<endIdx]
            let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 3 || parts.count == 4 {
                guard let r = Double(parts[0]),
                    let g = Double(parts[1]),
                    let b = Double(parts[2])
                else { return nil }
                let a = parts.count == 4 ? (Double(parts[3]) ?? 1.0) : 1.0
                let red = CGFloat(max(0, min(255, r))) / 255.0
                let green = CGFloat(max(0, min(255, g))) / 255.0
                let blue = CGFloat(max(0, min(255, b))) / 255.0
                let alpha = CGFloat(max(0, min(1.0, a)))
                return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
            }
        }

        // 3. Named colors
        switch lower {
        case "white": return .white
        case "black": return .black
        case "clear", "transparent": return .clear
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "gray", "grey": return .gray
        case "cyan": return .cyan
        case "magenta": return .magenta
        case "purple": return .purple
        default: return nil
        }
    }

    private static func luminance(of color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 1 }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }
}

enum ThemeOverride: String, CaseIterable {
    case server
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .server: return "Server (Default)"
        case .system: return "System (macOS)"
        case .light: return "Light (Denim)"
        case .dark: return "Dark (Onyx)"
        }
    }
}

@MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var theme: MMTheme = .denim
    /// True when the active server theme is "System" (or absent), in which case
    /// native controls should follow `NSApp.effectiveAppearance` instead of a
    /// forced light/dark appearance.
    private(set) var usesSystemAppearance = true
    private var lastPreferences: [[String: String]] = []
    private var lastTeamId: String?

    var themeOverride: ThemeOverride {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "themeOverride"),
                let override = ThemeOverride(rawValue: raw)
            else {
                return .server
            }
            return override
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "themeOverride")
            reapply()
        }
    }

    private init() {
        applySystemTheme()
    }

    /// Applies the theme preference for the active team, falling back to the global one.
    func apply(preferences: [[String: String]], teamId: String?) {
        lastPreferences = preferences
        lastTeamId = teamId

        switch themeOverride {
        case .system:
            applySystemTheme()
            return
        case .light:
            usesSystemAppearance = false
            theme = .denim
            return
        case .dark:
            usesSystemAppearance = false
            theme = .onyx
            return
        case .server:
            break
        }

        let themePreferences = preferences.filter { $0["category"] == "theme" }
        let teamKey = teamId ?? ""
        let preference =
            themePreferences.first { $0["name"] == teamKey }
            ?? themePreferences.first { $0["name"] == "" }
        guard let raw = preference?["value"],
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            applySystemTheme()
            return
        }
        if (json["type"] as? String)?.lowercased() == "system" {
            applySystemTheme()
            return
        }
        usesSystemAppearance = false
        theme = MMTheme(json: json)
    }

    /// Re-resolves a System theme after the macOS appearance changes.
    func reapply() {
        apply(preferences: lastPreferences, teamId: lastTeamId)
    }

    private func applySystemTheme() {
        usesSystemAppearance = true
        let appearance = NSApplication.shared.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        theme = isDark ? .onyx : .denim
    }
}
