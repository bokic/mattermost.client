//
//  MMFont.swift
//  mattermost.client
//
//  Typography helpers that mirror the Mattermost web client, which renders
//  with Open Sans. The font is bundled with the app and registered at launch;
//  if registration fails we degrade gracefully to the system font.
//

import AppKit
import CoreText

@MainActor
enum MMFont {

    /// Family used by the Mattermost web client (`font--open_sans` body class).
    static let familyName = "Open Sans"

    private static var didRegister = false

    /// Registers the bundled Open Sans variable font for the running process.
    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        guard let url = Bundle.main.url(forResource: "OpenSans", withExtension: "ttf") else {
            NSLog("MMFont: OpenSans.ttf not found in bundle; falling back to the system font.")
            return
        }

        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !registered, let error = error {
            NSLog("MMFont: failed to register Open Sans: \(error.takeRetainedValue())")
        }
    }

    /// Open Sans ships as a variable font; CoreText exposes named instances with
    /// these PostScript names. `OpenSans-SemiBold` is not resolvable, the Roman
    /// prefix is part of the instance name.
    private static func postScriptName(for weight: NSFont.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black:
            return "OpenSansRoman-Bold"
        case .semibold, .medium:
            return "OpenSansRoman-SemiBold"
        default:
            return "OpenSans-Regular"
        }
    }

    static func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        registerBundledFonts()
        if let font = NSFont(name: postScriptName(for: weight), size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func regular(_ size: CGFloat) -> NSFont { font(ofSize: size, weight: .regular) }
    static func medium(_ size: CGFloat) -> NSFont { font(ofSize: size, weight: .medium) }
    static func semibold(_ size: CGFloat) -> NSFont { font(ofSize: size, weight: .semibold) }
    static func bold(_ size: CGFloat) -> NSFont { font(ofSize: size, weight: .bold) }
}
