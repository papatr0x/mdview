import AppKit
import XCTest
@testable import mdview

/// Covers the settings layer through its own storage: every test runs against
/// a throwaway suite, never `UserDefaults.standard`, so running the suite
/// cannot disturb the settings of whoever ran it.
final class PreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "mdview.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - First run

    func testEmptyStoreYieldsTheDocumentedDefaults() {
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.fontFamily, "Courier New")
        XCTAssertEqual(preferences.fontSize, 13)
        XCTAssertTrue(preferences.boldHeadings)
        XCTAssertTrue(preferences.renumberOrderedLists)
        XCTAssertEqual(preferences.appearanceMode, .system)
        XCTAssertEqual(preferences.colorTheme, .default)
    }

    /// The toggles default to *on*, which only works because the read
    /// distinguishes "absent" from "false". Reading a missing key with
    /// `bool(forKey:)` would hand an upgrading user `false` instead.
    func testAbsentTogglesDefaultToOnRatherThanFalse() {
        XCTAssertNil(defaults.object(forKey: "mdview.renumberOrderedLists"))
        XCTAssertTrue(Preferences(defaults: defaults).renumberOrderedLists)

        defaults.set(false, forKey: "mdview.renumberOrderedLists")
        XCTAssertFalse(Preferences(defaults: defaults).renumberOrderedLists)
    }

    // MARK: - Persistence

    func testSettingsSurviveAReload() {
        let preferences = Preferences(defaults: defaults)
        preferences.fontFamily = "Menlo"
        preferences.fontSize = 21
        preferences.boldHeadings = false
        preferences.renumberOrderedLists = false
        preferences.appearanceMode = .dark
        preferences.colorTheme.light.colors[.heading1] = RGBAColor(red: 0.1, green: 0.8, blue: 0.3)

        let reloaded = Preferences(defaults: defaults)

        XCTAssertEqual(reloaded.fontFamily, "Menlo")
        XCTAssertEqual(reloaded.fontSize, 21)
        XCTAssertFalse(reloaded.boldHeadings)
        XCTAssertFalse(reloaded.renumberOrderedLists)
        XCTAssertEqual(reloaded.appearanceMode, .dark)
        XCTAssertEqual(
            reloaded.colorTheme.light.colors[.heading1],
            RGBAColor(red: 0.1, green: 0.8, blue: 0.3)
        )
    }

    // MARK: - Damaged storage

    func testUnreadableThemeFallsBackToTheDefaultTheme() {
        defaults.set(Data("not json".utf8), forKey: "mdview.colorTheme")

        XCTAssertEqual(Preferences(defaults: defaults).colorTheme, .default)
    }

    func testUnknownAppearanceModeFallsBackToSystem() {
        defaults.set("sepia", forKey: "mdview.appearanceMode")

        XCTAssertEqual(Preferences(defaults: defaults).appearanceMode, .system)
    }

    /// A stored size of zero is indistinguishable from "absent" through
    /// `double(forKey:)`, and a zero-point font would render nothing.
    func testZeroFontSizeFallsBackInsteadOfRenderingNothing() {
        defaults.set(0.0, forKey: "mdview.fontSize")

        XCTAssertEqual(Preferences(defaults: defaults).fontSize, 13)
    }

    // MARK: - Font size commands

    func testFontSizeStepsStayWithinRange() {
        let preferences = Preferences(defaults: defaults)

        preferences.fontSize = Preferences.fontSizeRange.upperBound
        preferences.increaseFontSize()
        XCTAssertEqual(preferences.fontSize, Preferences.fontSizeRange.upperBound)

        preferences.fontSize = Preferences.fontSizeRange.lowerBound
        preferences.decreaseFontSize()
        XCTAssertEqual(preferences.fontSize, Preferences.fontSizeRange.lowerBound)
    }
}
