//
//  LocalizationTests.swift
//  mattermost.clientTests
//

import AppKit
import Foundation
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class LocalizationTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        L10n.overrideLocale = nil
    }

    func testAvailableLocalesIncludesGerman() {
        let locales = L10n.availableLocales
        XCTAssertTrue(locales.contains("en") || locales.contains("Base"))
        XCTAssertTrue(locales.contains("de"), "Available locales should include 'de'")
    }

    func testDefaultStringsReturnEnglish() {
        L10n.overrideLocale = nil
        XCTAssertEqual(L10n.string("Sign in"), "Sign in")
        XCTAssertEqual(L10n.string("Server URL"), "Server URL")
        XCTAssertEqual(L10n.string("Password"), "Password")
        XCTAssertEqual(L10n.string("Search"), "Search")
        XCTAssertEqual(L10n.string("Settings"), "Settings")
        XCTAssertEqual(L10n.string("Browse Channels"), "Browse Channels")
        XCTAssertEqual(L10n.string("No channels found"), "No channels found")
        XCTAssertEqual(L10n.string("Online"), "Online")
        XCTAssertEqual(L10n.string("Away"), "Away")
        XCTAssertEqual(L10n.string("Do not disturb"), "Do not disturb")
        XCTAssertEqual(L10n.string("Offline"), "Offline")
    }

    func testFormattedStrings() {
        L10n.overrideLocale = nil
        let formatted = L10n.format("Write to %@", "Town Square")
        XCTAssertEqual(formatted, "Write to Town Square")

        let dmCount = L10n.format("%d members (up to 7)", 3)
        XCTAssertEqual(dmCount, "3 members (up to 7)")

        let goButton = L10n.format("Go (%d)", 4)
        XCTAssertEqual(goButton, "Go (4)")
    }

    func testGermanTranslationsViaLocalizedString() {
        XCTAssertEqual(L10n.localizedString(for: "Sign in", locale: "de"), "Anmelden")
        XCTAssertEqual(L10n.localizedString(for: "Settings", locale: "de"), "Einstellungen")
        XCTAssertEqual(L10n.localizedString(for: "Browse Channels", locale: "de"), "Kanäle durchsuchen")
        XCTAssertEqual(L10n.localizedString(for: "Password", locale: "de"), "Passwort")
        XCTAssertEqual(L10n.localizedString(for: "Search", locale: "de"), "Suchen")
        XCTAssertEqual(L10n.localizedString(for: "Delete", locale: "de"), "Löschen")
        XCTAssertEqual(L10n.localizedString(for: "Retry", locale: "de"), "Erneut versuchen")
        XCTAssertEqual(L10n.localizedString(for: "No channels found", locale: "de"), "Keine Kanäle gefunden")
    }

    func testDynamicLocaleOverrideToGerman() {
        L10n.overrideLocale = "de"

        XCTAssertEqual(L10n.string("Sign in"), "Anmelden")
        XCTAssertEqual(L10n.string("Find server by email"), "Server per E-Mail finden")
        XCTAssertEqual(L10n.string("Password"), "Passwort")
        XCTAssertEqual(L10n.string("Search"), "Suchen")
        XCTAssertEqual(L10n.string("Settings"), "Einstellungen")
        XCTAssertEqual(L10n.string("Browse Channels"), "Kanäle durchsuchen")
        XCTAssertEqual(L10n.string("Online"), "Online")
        XCTAssertEqual(L10n.string("Away"), "Abwesend")
        XCTAssertEqual(L10n.string("Do not disturb"), "Bitte nicht stören")
        XCTAssertEqual(L10n.string("Offline"), "Offline")
        XCTAssertEqual(L10n.string("Channels"), "Kanäle")
        XCTAssertEqual(L10n.string("Invite People"), "Personen einladen")
        XCTAssertEqual(L10n.string("Team Members"), "Teammitglieder")
        XCTAssertEqual(L10n.string("Team Settings"), "Teameinstellungen")
        XCTAssertEqual(L10n.string("Leave Team"), "Team verlassen")
        XCTAssertEqual(L10n.string("Desktop notifications"), "Desktop-Benachrichtigungen")
        XCTAssertEqual(L10n.string("Notification sound"), "Benachrichtigungston")
        XCTAssertEqual(L10n.string("No muted channels"), "Keine stummgeschalteten Kanäle")
        XCTAssertEqual(L10n.string("Theme override"), "Design-Überschreibung")
        XCTAssertEqual(L10n.string("No channels found"), "Keine Kanäle gefunden")
    }

    func testDatesFollowLocale() {
        let date = Date(timeIntervalSince1970: 1700000000)

        let enFormatter = DateFormatter()
        enFormatter.locale = Locale(identifier: "en_US")
        enFormatter.dateStyle = .medium
        enFormatter.timeStyle = .short

        let deFormatter = DateFormatter()
        deFormatter.locale = Locale(identifier: "de_DE")
        deFormatter.dateStyle = .medium
        deFormatter.timeStyle = .short

        let enString = enFormatter.string(from: date)
        let deString = deFormatter.string(from: date)

        XCTAssertNotEqual(enString, deString)
        XCTAssertTrue(deString.contains("."))
    }
}
