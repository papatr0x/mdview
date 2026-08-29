import AppKit
import XCTest
@testable import mdview

/// A saved theme outlives the build that wrote it, in both directions: it is
/// read back by later versions that know more node kinds, and by earlier ones
/// that know fewer. These pin both.
final class ColorThemeTests: XCTestCase {
    /// The stored `colors` map, as `JSONEncoder` writes it: a flat array of
    /// alternating raw kind and color.
    private func storedTheme(
        light: [(String, RGBAColor)],
        dark: [(String, RGBAColor)]
    ) throws -> Data {
        func palette(_ entries: [(String, RGBAColor)]) -> [String: Any] {
            var colors: [Any] = []
            for (kind, color) in entries {
                colors.append(kind)
                colors.append([
                    "red": color.red, "green": color.green,
                    "blue": color.blue, "alpha": color.alpha
                ])
            }
            return ["colors": colors]
        }
        return try JSONSerialization.data(
            withJSONObject: ["light": palette(light), "dark": palette(dark)]
        )
    }

    private let red = RGBAColor(red: 1, green: 0, blue: 0)

    /// A kind added after the theme was written is missing from it, and used to
    /// fall through to the *light* defaults whichever palette was being read —
    /// `color(for:)` cannot tell which appearance it belongs to. In dark that
    /// meant a new kind arriving as near-black text on a near-black page.
    func testMissingKindsAreFilledFromTheMatchingAppearance() throws {
        let data = try storedTheme(
            light: [(MarkdownNodeKind.heading1.rawValue, red)],
            dark: [(MarkdownNodeKind.heading1.rawValue, red)]
        )
        let theme = try JSONDecoder().decode(ColorTheme.self, from: data)

        // What the file did carry survives.
        XCTAssertEqual(theme.light.colors[.heading1], red)
        XCTAssertEqual(theme.dark.colors[.heading1], red)

        // Everything it did not is filled per appearance, not from light twice.
        for kind in MarkdownNodeKind.allCases where kind != .heading1 {
            XCTAssertEqual(theme.light.colors[kind], ColorPalette.defaultLight.colors[kind],
                           "\(kind.rawValue) should fall back to the light default")
            XCTAssertEqual(theme.dark.colors[kind], ColorPalette.defaultDark.colors[kind],
                           "\(kind.rawValue) should fall back to the dark default, not the light one")
        }

        // The concrete symptom: body text stays readable on a dark page.
        XCTAssertEqual(theme.dark.color(for: .body), ColorPalette.defaultDark.color(for: .body))
        XCTAssertNotEqual(theme.dark.color(for: .body), ColorPalette.defaultLight.color(for: .body))
    }

    /// The synthesized dictionary decoder rejects the whole map over one raw
    /// value it does not know, and `Preferences` reads the theme with `try?` —
    /// so a theme written by a newer build used to wipe every color the user had
    /// chosen, in both palettes, without a word.
    func testUnknownNodeKindDoesNotDiscardTheTheme() throws {
        let data = try storedTheme(
            light: [
                (MarkdownNodeKind.heading1.rawValue, red),
                ("tableHeader", RGBAColor(red: 0, green: 1, blue: 0)),
                (MarkdownNodeKind.link.rawValue, red)
            ],
            dark: [(MarkdownNodeKind.heading1.rawValue, red)]
        )
        let theme = try JSONDecoder().decode(ColorTheme.self, from: data)

        // The unknown entry is skipped, and — the point — the known ones on
        // both sides of it are kept.
        XCTAssertEqual(theme.light.colors[.heading1], red)
        XCTAssertEqual(theme.light.colors[.link], red)
        XCTAssertEqual(theme.dark.colors[.heading1], red)
    }

    /// The encoded form has to stay readable by builds that predate this fix,
    /// so only decoding was made lenient.
    func testEncodedThemeRoundTrips() throws {
        var theme = ColorTheme.default
        theme.dark.colors[.link] = red
        theme.light.background = RGBAColor(red: 0.5, green: 0.5, blue: 0.5)

        let decoded = try JSONDecoder().decode(
            ColorTheme.self,
            from: try JSONEncoder().encode(theme)
        )
        XCTAssertEqual(decoded, theme)
    }
}
