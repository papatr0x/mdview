import AppKit
import XCTest
@testable import mdview

/// Hiding the `**`/`*`/`_` around emphasis and the backticks around inline code
/// is a *layout* change, not a text one: the characters stay in the string and
/// are dropped when glyphs are generated. These pin both halves — which
/// characters get marked, and that the marked ones really produce no glyph —
/// and, above all, that the document is still the file.
@MainActor
final class InlineDelimiterTests: XCTestCase {
    private func style() -> MarkdownStyle {
        MarkdownStyle(
            theme: .default,
            bodyFontName: "Helvetica",
            bodyFontSize: 13,
            codeFontName: "Menlo",
            codeFontSize: 13,
            isDarkAppearance: false,
            boldHeadings: true,
            listItemSpacing: 6
        )
    }

    /// Adjacent runs carrying the same value come back merged, which is what is
    /// wanted: what matters is which characters end up hidden, not which node
    /// claimed each one.
    private func hiddenRanges(in attributed: NSAttributedString) -> [NSRange] {
        var ranges: [NSRange] = []
        attributed.enumerateAttribute(
            .hiddenMarkdownDelimiter,
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        return ranges
    }

    private func hiddenText(in attributed: NSAttributedString) -> String {
        let text = attributed.string as NSString
        return hiddenRanges(in: attributed).map { text.substring(with: $0) }.joined(separator: "|")
    }

    // MARK: - Which characters get marked

    func testBoldAsterisksAreMarkedAndTheWordIsNot() {
        let source = "plain **bold** text"
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(hiddenRanges(in: attributed),
                       [NSRange(location: 6, length: 2), NSRange(location: 12, length: 2)])
        XCTAssertEqual(hiddenText(in: attributed), "**|**")
    }

    func testEachDelimiterSpellingIsMarked() {
        for (source, expected) in [("a **bold** b", "**|**"),
                                   ("a __bold__ b", "__|__"),
                                   ("a *italic* b", "*|*"),
                                   ("a _italic_ b", "_|_"),
                                   ("a `code` b", "`|`"),
                                   ("a ``code`` b", "``|``"),
                                   ("a `` ` `` b", "``|``")] {
            let attributed = MarkdownRenderer.render(markdown: source, style: style())
            XCTAssertEqual(hiddenText(in: attributed), expected, "for \(source)")
        }
    }

    /// All six asterisks go; the word between them stays.
    func testBoldItalicHidesAllSixAsterisksAndNothingElse() {
        let source = "***both***"
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(hiddenRanges(in: attributed),
                       [NSRange(location: 0, length: 3), NSRange(location: 7, length: 3)])
        XCTAssertNil(attributed.attribute(.hiddenMarkdownDelimiter, at: 3, effectiveRange: nil),
                     "the word itself must stay visible")
    }

    /// Only the delimiters of a real inline node are touched. Inside a code
    /// span the asterisks are content, so the backticks go and they stay.
    func testMarkupInsideCodeIsLeftAlone() {
        let source = "a `**not bold**` b\n"
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(hiddenText(in: attributed), "`|`")
        for characterIndex in [3, 4, 13, 14] {
            XCTAssertNil(
                attributed.attribute(.hiddenMarkdownDelimiter, at: characterIndex, effectiveRange: nil),
                "the asterisk at \(characterIndex) is code content, not a marker"
            )
        }
    }

    /// Characters that never belonged to an inline node stay put: a fenced
    /// block's own fences are not a code *span*, and loose asterisks are text.
    func testCharactersOutsideAnInlineNodeStayVisible() {
        for source in ["```\n**not bold**\n```\n", "2 * 3 * 4\n", "a ` b\n"] {
            let attributed = MarkdownRenderer.render(markdown: source, style: style())
            XCTAssertEqual(hiddenRanges(in: attributed), [], "for \(source.debugDescription)")
        }
    }

    /// A code span inside bold: each node claims its own delimiters and the two
    /// pairs never overlap. They do sit flush against each other, so each end
    /// comes back as one merged run rather than two.
    func testCodeInsideBoldHidesBothPairs() {
        let source = "a **`code`** b"
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(hiddenText(in: attributed), "**`|`**")
        XCTAssertEqual(attributed.string, source)
    }

    // MARK: - The document is still the file

    func testTheSourceTextIsUntouched() {
        let source = """
        # Title

        Some **bold**, some *italic*, some ***both***, and `**code**`.

        - **item**
        """
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(attributed.string, source,
                       "hiding is a layout decision — not one character may be removed")
    }

    /// Turning the setting off writes nothing at all, so the rendered document
    /// is attribute-for-attribute the one that came before the feature existed.
    func testDisablingLeavesTheRenderUntouched() {
        let source = "Some **bold** and *italic* text.\n"
        let off = MarkdownRenderer.render(markdown: source, style: style(), hideMarkdownMarkers: false)

        XCTAssertEqual(hiddenRanges(in: off), [])
        XCTAssertTrue(off.isEqual(to: MarkdownRenderer.render(
            plan: MarkdownRenderer.plan(for: source),
            markdown: source,
            style: style(),
            hideMarkdownMarkers: false
        )))
    }

    /// The ranges live in the plan and the setting is resolved when painting, so
    /// the toggle flips without rebuilding anything.
    func testTogglingReusesTheSamePlan() {
        let source = "a **bold** b\n"
        let plan = MarkdownRenderer.plan(for: source)

        let on = MarkdownRenderer.render(plan: plan, markdown: source, style: style(),
                                         hideMarkdownMarkers: true)
        let off = MarkdownRenderer.render(plan: plan, markdown: source, style: style(),
                                          hideMarkdownMarkers: false)

        XCTAssertEqual(hiddenText(in: on), "**|**")
        XCTAssertEqual(hiddenRanges(in: off), [])
        XCTAssertEqual(on.string, off.string)
    }

    /// Renumbering rewrites text and hiding does not, so the two have to agree
    /// about where things are once both have run.
    func testHidingCoexistsWithRenumbering() {
        let source = "1. **uno**\n1. **dos**\n1. **tres**\n"
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(attributed.string, "1. **uno**\n2. **dos**\n3. **tres**\n")
        XCTAssertEqual(hiddenText(in: attributed), "**|**|**|**|**|**")
        let text = attributed.string as NSString
        for range in hiddenRanges(in: attributed) {
            XCTAssertEqual(text.substring(with: range), "**", "a rewrite shifted a delimiter range")
        }
    }

    // MARK: - The glyphs actually go

    private func laidOutTextView(_ source: String, hiding: Bool) -> AppearanceAwareTextView {
        let textView = AppearanceAwareTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.layoutManager?.delegate = textView
        textView.textStorage?.setAttributedString(
            MarkdownRenderer.render(markdown: source, style: style(), hideMarkdownMarkers: hiding)
        )
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        return textView
    }

    func testMarkedCharactersGetNoGlyph() throws {
        let source = "a **bold** b"
        let textView = laidOutTextView(source, hiding: true)
        let layoutManager = try XCTUnwrap(textView.layoutManager)

        // "a " is 0-1, the opening "**" is 2-3, "bold" is 4-7.
        for characterIndex in [2, 3] {
            let glyph = layoutManager.glyphIndexForCharacter(at: characterIndex)
            XCTAssertEqual(layoutManager.propertyForGlyph(at: glyph), .null,
                           "the delimiter at \(characterIndex) should produce no glyph")
        }
        let wordGlyph = layoutManager.glyphIndexForCharacter(at: 4)
        XCTAssertNotEqual(layoutManager.propertyForGlyph(at: wordGlyph), .null,
                          "the word must still be drawn")
    }

    func testHidingMakesTheLineNarrower() throws {
        let source = "a **bold** b"
        let hidden = try XCTUnwrap(laidOutTextView(source, hiding: true).layoutManager)
        let shown = try XCTUnwrap(laidOutTextView(source, hiding: false).layoutManager)

        var ignored = NSRange()
        let hiddenWidth = hidden.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: &ignored).width
        let shownWidth = shown.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: &ignored).width

        XCTAssertLessThan(hiddenWidth, shownWidth,
                          "four hidden asterisks should take the line in, not just stop drawing")
    }
}
