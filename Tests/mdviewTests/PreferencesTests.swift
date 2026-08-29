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

        XCTAssertEqual(preferences.bodyFontFamily, "Courier New")
        XCTAssertEqual(preferences.bodyFontSize, 13)
        XCTAssertEqual(preferences.codeFontFamily, "Menlo")
        XCTAssertEqual(preferences.codeFontSize, 13)
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
        preferences.bodyFontFamily = "Georgia"
        preferences.bodyFontSize = 21
        preferences.codeFontFamily = "Menlo"
        preferences.codeFontSize = 15
        preferences.boldHeadings = false
        preferences.renumberOrderedLists = false
        preferences.appearanceMode = .dark
        preferences.colorTheme.light.colors[.heading1] = RGBAColor(red: 0.1, green: 0.8, blue: 0.3)

        let reloaded = Preferences(defaults: defaults)

        XCTAssertEqual(reloaded.bodyFontFamily, "Georgia")
        XCTAssertEqual(reloaded.bodyFontSize, 21)
        XCTAssertEqual(reloaded.codeFontFamily, "Menlo")
        XCTAssertEqual(reloaded.codeFontSize, 15)
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
        defaults.set(0.0, forKey: "mdview.codeFontSize")

        XCTAssertEqual(Preferences(defaults: defaults).bodyFontSize, 13)
        XCTAssertEqual(Preferences(defaults: defaults).codeFontSize, 13)
    }

    // MARK: - Font size commands

    func testFontSizeStepsStayWithinRange() {
        let preferences = Preferences(defaults: defaults)

        preferences.bodyFontSize = Preferences.fontSizeRange.upperBound
        preferences.codeFontSize = Preferences.fontSizeRange.upperBound
        preferences.increaseFontSize()
        XCTAssertEqual(preferences.bodyFontSize, Preferences.fontSizeRange.upperBound)
        XCTAssertEqual(preferences.codeFontSize, Preferences.fontSizeRange.upperBound)

        preferences.bodyFontSize = Preferences.fontSizeRange.lowerBound
        preferences.codeFontSize = Preferences.fontSizeRange.lowerBound
        preferences.decreaseFontSize()
        XCTAssertEqual(preferences.bodyFontSize, Preferences.fontSizeRange.lowerBound)
        XCTAssertEqual(preferences.codeFontSize, Preferences.fontSizeRange.lowerBound)
    }

    /// Zooming a document zooms all of it, both fonts at once.
    func testZoomMovesBothSizes() {
        let preferences = Preferences(defaults: defaults)
        preferences.bodyFontSize = 13
        preferences.codeFontSize = 16

        preferences.increaseFontSize()
        XCTAssertEqual(preferences.bodyFontSize, 14)
        XCTAssertEqual(preferences.codeFontSize, 17)

        preferences.decreaseFontSize()
        preferences.decreaseFontSize()
        XCTAssertEqual(preferences.bodyFontSize, 12)
        XCTAssertEqual(preferences.codeFontSize, 15)
    }

    // MARK: - Wiring into the renderer

    /// The settings reach the style object as two separate fonts. Cheap to
    /// assert and easy to get wrong: a rendered document is the only other
    /// place this shows up.
    func testStyleCarriesBothFontsSeparately() {
        let preferences = Preferences(defaults: defaults)
        preferences.bodyFontFamily = "Georgia"
        preferences.bodyFontSize = 18
        preferences.codeFontFamily = "Menlo"
        preferences.codeFontSize = 12

        let style = preferences.style(isDarkAppearance: false)

        XCTAssertEqual(style.bodyFontName, "Georgia")
        XCTAssertEqual(style.bodyFontSize, 18)
        XCTAssertEqual(style.codeFontName, "Menlo")
        XCTAssertEqual(style.codeFontSize, 12)
        XCTAssertEqual(style.font(for: .body).familyName, "Georgia")
        XCTAssertEqual(style.font(for: .codeBlock).familyName, "Menlo")
        XCTAssertEqual(style.font(for: .inlineCode).pointSize, 12)
    }

    // MARK: - Upgrading from a single font

    /// A store written by a build that had one font setting. That family was
    /// necessarily fixed-width — the picker offered nothing else — so it seeds
    /// the code font rather than leaving the user with a family they never
    /// chose, and it stays the body font because the key never changed.
    func testStoreFromTheSingleFontBuildSeedsBothFonts() {
        defaults.set("Courier", forKey: "mdview.fontFamily")
        defaults.set(17.0, forKey: "mdview.fontSize")

        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.bodyFontFamily, "Courier")
        XCTAssertEqual(preferences.bodyFontSize, 17)
        XCTAssertEqual(preferences.codeFontFamily, "Courier")
        XCTAssertEqual(preferences.codeFontSize, 17)
    }

    /// Once the code font has been chosen explicitly it stops following the
    /// body one.
    func testExplicitCodeFontWinsOverTheBodyFamily() {
        defaults.set("Courier", forKey: "mdview.fontFamily")
        defaults.set("Menlo", forKey: "mdview.codeFontFamily")

        XCTAssertEqual(Preferences(defaults: defaults).codeFontFamily, "Menlo")
    }
}
