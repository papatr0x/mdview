import AppKit
import XCTest
@testable import mdview

/// Headings and quotes carry their structure in their marker, unlike emphasis,
/// which carries it in the font. So hiding `#` and `>` only works if they are
/// given a shape of their own first: a size per heading level, and an indent
/// with a rule for a quote. These pin both halves.
final class HeadingAndQuoteTests: XCTestCase {
    private func style(size: CGFloat = 13, bold: Bool = true, spacing: CGFloat = 6) -> MarkdownStyle {
        MarkdownStyle(
            theme: .default,
            bodyFontName: "Helvetica",
            bodyFontSize: size,
            codeFontName: "Menlo",
            codeFontSize: size,
            isDarkAppearance: false,
            boldHeadings: bold,
            listItemSpacing: spacing
        )
    }

    private func hiddenText(in attributed: NSAttributedString) -> String {
        let text = attributed.string as NSString
        var pieces: [String] = []
        attributed.enumerateAttribute(
            .hiddenMarkdownDelimiter,
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { value, range, _ in
            if value != nil { pieces.append(text.substring(with: range)) }
        }
        return pieces.joined(separator: "|")
    }

    private func paragraphStyle(
        in attributed: NSAttributedString,
        at substring: String
    ) throws -> NSParagraphStyle {
        let location = (attributed.string as NSString).range(of: substring).location
        XCTAssertNotEqual(location, NSNotFound, "\(substring) not found")
        return try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        )
    }

    // MARK: - Heading sizes

    /// Strictly decreasing, and — the part that matters now that headings have
    /// no colour and no `#` — no level lands on the body size. One that did
    /// would be indistinguishable from ordinary text.
    func testHeadingSizesDecreaseAndNoneMatchesTheBody() {
        let currentStyle = style(size: 14)
        let sizes = (1...6).map { currentStyle.headingFont(level: $0).pointSize }

        for (level, size) in sizes.enumerated() {
            XCTAssertNotEqual(size, currentStyle.baseFont.pointSize,
                              "H\(level + 1) is the same size as body text")
        }
        XCTAssertEqual(sizes, sizes.sorted(by: >), "the scale must fall from H1 to H6")
        XCTAssertEqual(Set(sizes).count, sizes.count, "two levels share a size")
    }

    /// The scale is relative, so Cmd+ and Cmd- carry the headings with them.
    func testHeadingSizesFollowTheBodySize() {
        let small = style(size: 12).headingFont(level: 1).pointSize
        let large = style(size: 24).headingFont(level: 1).pointSize

        XCTAssertGreaterThan(large, small)
    }

    func testDeeperHeadingsGetSmallerFonts() {
        let currentStyle = style()
        let source = "# One\n\n## Two\n\n###### Six\n"
        let attributed = MarkdownRenderer.render(markdown: source, style: currentStyle)
        let text = attributed.string as NSString

        func size(of substring: String) -> CGFloat? {
            let location = text.range(of: substring).location
            return (attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont)?.pointSize
        }

        XCTAssertEqual(size(of: "One"), currentStyle.headingFont(level: 1).pointSize)
        XCTAssertEqual(size(of: "Two"), currentStyle.headingFont(level: 2).pointSize)
        XCTAssertEqual(size(of: "Six"), currentStyle.headingFont(level: 6).pointSize)
    }

    // MARK: - Heading markers

    /// The spaces after the `#` go with it: leaving them would push the title
    /// in by a space against everything around it.
    func testHeadingHashAndTheSpaceAfterItAreHidden() {
        let attributed = MarkdownRenderer.render(markdown: "## Title\n", style: style())
        XCTAssertEqual(hiddenText(in: attributed), "## ")
    }

    /// CommonMark lets a heading close with a second run of hashes.
    func testClosingHashSequenceIsHidden() {
        let attributed = MarkdownRenderer.render(markdown: "## Title ##\n", style: style())
        XCTAssertEqual(hiddenText(in: attributed), "## | ##")
    }

    /// A hash inside the title is content, not a marker.
    func testHashInsideATitleStays() {
        let attributed = MarkdownRenderer.render(markdown: "# C# and F#\n", style: style())
        XCTAssertEqual(hiddenText(in: attributed), "# ")
    }

    /// A setext heading has no hashes to hide, and its underline is content.
    func testSetextHeadingIsLeftAlone() {
        let attributed = MarkdownRenderer.render(markdown: "Title\n=====\n", style: style())
        XCTAssertEqual(hiddenText(in: attributed), "")
    }

    // MARK: - Quote markers

    /// The `>` is on every line of a quote, not just the first.
    func testEveryQuotedLineLosesItsMarker() {
        let attributed = MarkdownRenderer.render(markdown: "> one\n> two\n> three\n", style: style())
        XCTAssertEqual(hiddenText(in: attributed), "> |> |> ")
    }

    func testNestedQuoteLosesBothMarkers() {
        let attributed = MarkdownRenderer.render(markdown: "> > deep\n", style: style())
        XCTAssertEqual(hiddenText(in: attributed), "> > ")
    }

    // MARK: - Quote shape

    func testQuoteIsIndentedAndCarriesItsLevel() throws {
        let source = "Intro.\n\n> quoted line\n"
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        let quoted = try paragraphStyle(in: attributed, at: "quoted")
        XCTAssertEqual(quoted.headIndent, MarkdownStyle.blockquoteIndent)
        XCTAssertEqual(quoted.firstLineHeadIndent, MarkdownStyle.blockquoteIndent)

        let location = (attributed.string as NSString).range(of: "quoted").location
        XCTAssertEqual(attributed.attribute(.blockquoteLevel, at: location, effectiveRange: nil) as? Int, 1)

        // Ordinary text is not moved.
        let intro = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(intro?.headIndent ?? 0, 0)
    }

    func testNestedQuoteIndentsTwice() throws {
        let attributed = MarkdownRenderer.render(markdown: "> > deep\n", style: style())

        XCTAssertEqual(try paragraphStyle(in: attributed, at: "deep").headIndent,
                       MarkdownStyle.blockquoteIndent * 2)
        let location = (attributed.string as NSString).range(of: "deep").location
        XCTAssertEqual(attributed.attribute(.blockquoteLevel, at: location, effectiveRange: nil) as? Int, 2)
    }

    /// The reason paragraph styles are merged rather than assigned. A list
    /// inside a quote is the one place two paragraph-level attributes meet, and
    /// with `addAttribute` replacing the whole object one of them would simply
    /// vanish depending on which ran last.
    func testAListInsideAQuoteKeepsBothIndentAndSpacing() throws {
        let source = "Intro.\n\n> - alfa\n> - beta\n"
        let attributed = MarkdownRenderer.render(markdown: source, style: style(spacing: 7))

        for item in ["alfa", "beta"] {
            let paragraph = try paragraphStyle(in: attributed, at: item)
            XCTAssertEqual(paragraph.headIndent, MarkdownStyle.blockquoteIndent,
                           "\(item) lost the quote indent")
            XCTAssertEqual(paragraph.paragraphSpacingBefore, 7,
                           "\(item) lost the list-item spacing")
        }
    }

    // MARK: - Where the bars land

    /// A quote's run starts on the hidden `>`, and TextKit packs that null
    /// glyph onto the end of the *previous* line's fragment — it has no width,
    /// so it fits there. Anchoring the bars on the run therefore picked the
    /// line above: every bar sat one line high, and one was left standing on
    /// the blank line between two quotes. They anchor on drawn content instead.
    @MainActor
    func testBarsSitOnTheQuotedLineNotTheOneAbove() throws {
        let source = "Intro.\n\n> quoted\n"
        let textView = AppearanceAwareTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.layoutManager?.delegate = textView
        textView.textStorage?.setAttributedString(
            MarkdownRenderer.render(markdown: source, style: style())
        )
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let text = source as NSString

        let quoteLine = text.paragraphRange(for: text.range(of: "quoted"))
        let anchor = try XCTUnwrap(textView.drawnGlyph(on: quoteLine, in: text, layoutManager))
        let barY = layoutManager.lineFragmentUsedRect(forGlyphAt: anchor, effectiveRange: nil).minY

        // The bar has to line up with the quoted text itself...
        let wordGlyph = layoutManager.glyphIndexForCharacter(at: text.range(of: "quoted").location)
        XCTAssertEqual(barY, layoutManager.lineFragmentUsedRect(forGlyphAt: wordGlyph, effectiveRange: nil).minY)

        // ...and not with the blank line above it.
        let introGlyph = layoutManager.glyphIndexForCharacter(at: 0)
        XCTAssertGreaterThan(barY, layoutManager.lineFragmentUsedRect(forGlyphAt: introGlyph, effectiveRange: nil).minY)
    }

    /// A line holding nothing but markers has no text to put a bar beside.
    @MainActor
    func testALineOfOnlyMarkersHasNoAnchor() throws {
        let source = ">\n"
        let textView = AppearanceAwareTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.layoutManager?.delegate = textView
        textView.textStorage?.setAttributedString(
            MarkdownRenderer.render(markdown: source, style: style())
        )
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        XCTAssertNil(textView.drawnGlyph(on: NSRange(location: 0, length: 2),
                                         in: source as NSString,
                                         layoutManager))
    }

    // MARK: - Still the file

    func testTheSourceTextIsUntouched() {
        let source = "# Title\n\n> quoted\n> more\n\n> > deeper\n"
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(attributed.string, source)
    }

    func testDisablingTheSettingRestoresEveryMarker() {
        let source = "## Title ##\n\n> quoted\n"
        let off = MarkdownRenderer.render(markdown: source, style: style(), hideMarkdownMarkers: false)

        XCTAssertEqual(hiddenText(in: off), "")
        // The shape stays: only the markers are governed by the setting.
        XCTAssertNotNil(off.attribute(.blockquoteLevel,
                                      at: (source as NSString).range(of: "quoted").location,
                                      effectiveRange: nil))
    }
}
