import AppKit
import XCTest
@testable import mdview

/// Regression tests for defects found in the pre-release audit.
final class RobustnessTests: XCTestCase {
    private func style() -> MarkdownStyle {
        MarkdownStyle(
            theme: .default,
            bodyFontName: "Helvetica",
            bodyFontSize: 13,
            codeFontName: "Menlo",
            codeFontSize: 13,
            isDarkAppearance: false,
            boldHeadings: true,
            listItemSpacing: 4
        )
    }

    private func charactersColored(_ color: NSColor, in attributed: NSAttributedString) -> Int {
        var count = 0
        for i in 0..<attributed.length
        where (attributed.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor) == color {
            count += 1
        }
        return count
    }

    // MARK: - Color conversion

    func testPatternColorIsRejectedInsteadOfCrashing() {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        image.unlockFocus()

        // A pattern color has no RGB components; reading them raises an
        // NSException, so conversion must fail rather than attempt it.
        XCTAssertNil(RGBAColor(NSColor(patternImage: image)))
        XCTAssertNotNil(RGBAColor(.systemBlue))
    }

    func testPaletteFallsBackWhenColorIsMissing() {
        let empty = ColorPalette(
            background: RGBAColor(red: 1, green: 1, blue: 1),
            codeBlockBackground: RGBAColor(red: 0, green: 0, blue: 0),
            colors: [:]
        )
        // Missing entries resolve through the light defaults rather than trapping.
        XCTAssertEqual(empty.color(for: .heading1), ColorPalette.defaultLight.color(for: .heading1))
    }

    /// A theme persisted before the background keys existed must pick up each
    /// side's own defaults — filling the dark palette from the light ones
    /// would give a dark document a white page.
    func testThemePersistedWithoutBackgroundsMigratesPerSide() throws {
        // Derived from a real encoding rather than hand-written, so the test
        // cannot drift from the format actually stored in UserDefaults.
        let current = try JSONEncoder().encode(ColorTheme.default)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: current) as? [String: Any]
        )
        for side in ["light", "dark"] {
            var palette = try XCTUnwrap(object[side] as? [String: Any])
            palette.removeValue(forKey: "background")
            palette.removeValue(forKey: "codeBlockBackground")
            object[side] = palette
        }
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let theme = try JSONDecoder().decode(ColorTheme.self, from: legacy)

        XCTAssertEqual(theme.light.background, ColorPalette.defaultLight.background)
        XCTAssertEqual(theme.dark.background, ColorPalette.defaultDark.background)
        XCTAssertEqual(theme.light.codeBlockBackground, ColorPalette.defaultLight.codeBlockBackground)
        XCTAssertEqual(theme.dark.codeBlockBackground, ColorPalette.defaultDark.codeBlockBackground)
        XCTAssertNotEqual(theme.dark.background, theme.light.background)
    }

    func testThemeRoundTripsThroughJSON() throws {
        var theme = ColorTheme.default
        theme.dark.background = RGBAColor(red: 0.2, green: 0.1, blue: 0.3)
        theme.light.colors[.heading1] = RGBAColor(red: 0.9, green: 0.1, blue: 0.1)

        let decoded = try JSONDecoder().decode(
            ColorTheme.self,
            from: try JSONEncoder().encode(theme)
        )
        XCTAssertEqual(decoded, theme)
    }

    // MARK: - List markers

    func testDashMarkerColorsOnlyTheMarker() {
        let attributed = MarkdownRenderer.render(markdown: "- item\n", style: style())
        XCTAssertEqual(charactersColored(style().color(for: .listMarker), in: attributed), 1)
    }

    func testTabSeparatedMarkerColorsOnlyTheMarker() {
        let attributed = MarkdownRenderer.render(markdown: "-\titem one\n", style: style())
        XCTAssertEqual(charactersColored(style().color(for: .listMarker), in: attributed), 1)
    }

    func testOrderedMarkerColorsOnlyTheMarker() {
        let attributed = MarkdownRenderer.render(markdown: "1. item\n", style: style())
        XCTAssertEqual(charactersColored(style().color(for: .listMarker), in: attributed), 2) // "1."
    }

    // MARK: - Inline code trait inheritance

    func testInlineCodeInsideBoldStaysBold() {
        let text = "**bold with `code` inside**\n"
        let attributed = MarkdownRenderer.render(markdown: text, style: style())
        let index = (attributed.string as NSString).range(of: "code").location
        let font = attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont

        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        XCTAssertTrue(traits.contains(.boldFontMask), "inline code should inherit the enclosing bold")
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false,
                      "inline code should still be monospaced")
    }

    func testInlineCodeInsideItalicStaysItalic() {
        let text = "*italic with `code` inside*\n"
        let attributed = MarkdownRenderer.render(markdown: text, style: style())
        let index = (attributed.string as NSString).range(of: "code").location
        let font = attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont

        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        XCTAssertTrue(traits.contains(.italicFontMask), "inline code should inherit the enclosing italic")
    }

    // MARK: - File decoding

    /// The same document written in every encoding mdview claims to accept
    /// must decode to identical text. UTF-16 without a byte-order mark is the
    /// interesting one: it is not self-describing, and a naive single-byte
    /// fallback turns it into text riddled with NUL characters.
    @MainActor
    func testAllSupportedEncodingsDecodeIdentically() throws {
        let expected = "# Título café\n\nBody ñ text.\n"

        let variants: [(name: String, data: Data)] = [
            ("utf8", try XCTUnwrap(expected.data(using: .utf8))),
            ("utf8-with-BOM", Data([0xEF, 0xBB, 0xBF]) + (try XCTUnwrap(expected.data(using: .utf8)))),
            ("latin1", try XCTUnwrap(expected.data(using: .isoLatin1))),
            ("utf16-with-BOM", try XCTUnwrap(expected.data(using: .utf16))),
            ("utf16LE-no-BOM", try XCTUnwrap(expected.data(using: .utf16LittleEndian))),
            ("utf16BE-no-BOM", try XCTUnwrap(expected.data(using: .utf16BigEndian)))
        ]

        for variant in variants {
            let text = try TextDecoder.decode(variant.data)
            XCTAssertEqual(text, expected, "\(variant.name) decoded incorrectly")
            XCTAssertFalse(text.unicodeScalars.contains { $0.value == 0 },
                           "\(variant.name) decoded with stray NUL characters")
            // Whether Foundation strips a byte-order mark varies by OS
            // version, so assert it explicitly rather than by luck.
            XCTAssertNotEqual(text.unicodeScalars.first?.value, 0xFEFF,
                              "\(variant.name) kept a leading byte-order mark")
        }
    }

    /// Whether Foundation strips a decoded byte-order mark depends on the OS
    /// version (macOS 14 keeps it, later releases do not), so the normalisation
    /// is tested directly rather than relying on the host's behaviour.
    func testByteOrderMarkStripping() {
        XCTAssertEqual(TextDecoder.strippingByteOrderMark("\u{FEFF}# Heading\n"), "# Heading\n")
        XCTAssertEqual(TextDecoder.strippingByteOrderMark("# Heading\n"), "# Heading\n")
        XCTAssertEqual(TextDecoder.strippingByteOrderMark(""), "")
        // Only a *leading* mark is removed; one mid-document is content.
        XCTAssertEqual(TextDecoder.strippingByteOrderMark("a\u{FEFF}b"), "a\u{FEFF}b")
        // A single mark, not a run of them.
        XCTAssertEqual(TextDecoder.strippingByteOrderMark("\u{FEFF}\u{FEFF}x"), "\u{FEFF}x")
    }

    func testASCIIDecodesVerbatim() throws {
        let original = "# Plain Heading\n\n- item\n\n```\ncode\n```\n"
        let data = try XCTUnwrap(original.data(using: .ascii))
        XCTAssertEqual(try TextDecoder.decode(data), original)
    }

    func testLatin1IsNotValidUTF8ButStillDecodes() throws {
        let latin1 = try XCTUnwrap("# Título café\n".data(using: .isoLatin1))
        XCTAssertNil(String(data: latin1, encoding: .utf8), "fixture must not be valid UTF-8")
        XCTAssertTrue(try TextDecoder.decode(latin1).contains("Título"))
    }

    func testUTF8DecodesVerbatim() throws {
        let original = "# Título café 日本語 🎉\n"
        let data = try XCTUnwrap(original.data(using: .utf8))
        XCTAssertEqual(try TextDecoder.decode(data), original)
    }

    func testOversizedDataIsRejected() {
        let data = Data(count: TextDecoder.maximumFileSize + 1)
        XCTAssertThrowsError(try TextDecoder.decode(data))
    }

    /// The whole path a window runs on open: decode the bytes, hand them to a
    /// document, then highlight them with the shared display settings.
    func testDocumentTextIsDecodedAndHighlighted() throws {
        let source = "# Título con acentos\n\nCafé, ñandú.\n\n```\nlet x = 1\n```\n"
        let data = try XCTUnwrap(source.data(using: .isoLatin1))

        let document = MarkdownDocument(text: try TextDecoder.decode(data))
        XCTAssertTrue(document.text.contains("Título con acentos"))
        XCTAssertTrue(document.text.contains("ñandú"))

        let rendered = MarkdownRenderer.render(markdown: document.text, style: style())
        let headingIndex = (rendered.string as NSString).range(of: "Título").location
        XCTAssertNotEqual(headingIndex, NSNotFound)
        let headingFont = try XCTUnwrap(rendered.attribute(.font, at: headingIndex, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: headingFont).contains(.boldFontMask))

        let codeIndex = (rendered.string as NSString).range(of: "let x = 1").location
        XCTAssertNotNil(rendered.attribute(.backgroundColor, at: codeIndex, effectiveRange: nil))
    }
}
