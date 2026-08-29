import AppKit
import XCTest
@testable import mdview

/// Vertical space before list items is a *layout* attribute, not a text one:
/// the rendered string still matches the file character for character. These
/// pin where the space lands and, just as importantly, where it does not.
final class ListSpacingTests: XCTestCase {
    private func style(spacing: CGFloat = 6) -> MarkdownStyle {
        MarkdownStyle(
            theme: .default,
            bodyFontName: "Helvetica",
            bodyFontSize: 13,
            codeFontName: "Menlo",
            codeFontSize: 13,
            isDarkAppearance: false,
            boldHeadings: true,
            listItemSpacing: spacing
        )
    }

    private func spacingBefore(in attributed: NSAttributedString, at substring: String) -> CGFloat? {
        let location = (attributed.string as NSString).range(of: substring).location
        guard location != NSNotFound else { return nil }
        let paragraphStyle = attributed.attribute(
            .paragraphStyle,
            at: location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        return paragraphStyle?.paragraphSpacingBefore
    }

    // MARK: - Where the space lands

    func testUnorderedItemsGetSpaceBefore() {
        let attributed = MarkdownRenderer.render(markdown: "- one\n- two\n", style: style())

        XCTAssertEqual(spacingBefore(in: attributed, at: "one"), 6)
        XCTAssertEqual(spacingBefore(in: attributed, at: "two"), 6)
    }

    func testOrderedItemsGetSpaceBefore() {
        let attributed = MarkdownRenderer.render(markdown: "1. one\n1. two\n", style: style())

        XCTAssertEqual(spacingBefore(in: attributed, at: "one"), 6)
        XCTAssertEqual(spacingBefore(in: attributed, at: "two"), 6)
    }

    /// It applies before every item, the first one included.
    func testTheFirstItemOfAListIsSpacedToo() {
        let attributed = MarkdownRenderer.render(markdown: "text\n\n- first\n", style: style())

        XCTAssertEqual(spacingBefore(in: attributed, at: "first"), 6)
    }

    func testNestedItemsAreSpacedAsWell() {
        let source = """
        - outer
          - inner
        """
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(spacingBefore(in: attributed, at: "outer"), 6)
        XCTAssertEqual(spacingBefore(in: attributed, at: "inner"), 6)
    }

    // MARK: - Where it must not land

    func testOrdinaryParagraphsAreNotSpaced() {
        let attributed = MarkdownRenderer.render(
            markdown: "just a paragraph\n\n# and a heading\n",
            style: style()
        )

        XCTAssertNil(spacingBefore(in: attributed, at: "paragraph"))
        XCTAssertNil(spacingBefore(in: attributed, at: "heading"))
    }

    /// An item's range covers everything it contains. Spacing the whole range
    /// would push apart each paragraph inside the item instead of the item.
    func testOnlyTheItemsFirstLineIsSpaced() {
        let source = """
        - first line

          second paragraph of the same item
        """
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(spacingBefore(in: attributed, at: "first line"), 6)
        XCTAssertNil(spacingBefore(in: attributed, at: "second paragraph"))
    }

    /// A fenced block inside a list item keeps its own lines unspaced, which is
    /// what leaves its full-width background a solid rectangle.
    func testFencedBlockInsideAnItemIsNotSpaced() {
        let source = """
        - item

          ```
          let x = 1
          ```
        """
        let attributed = MarkdownRenderer.render(markdown: source, style: style())

        XCTAssertEqual(spacingBefore(in: attributed, at: "item"), 6)
        XCTAssertNil(spacingBefore(in: attributed, at: "let x = 1"))
    }

    // MARK: - Switching it off

    /// Zero writes no attribute at all, so the result is indistinguishable from
    /// a build without the feature — not merely "spaced by zero".
    func testZeroSpacingLeavesTheDocumentUntouched() {
        let source = "text\n\n- one\n- two\n\n1. a\n1. b\n"
        let attributed = MarkdownRenderer.render(markdown: source, style: style(spacing: 0))

        XCTAssertNil(attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil))
        for index in 0..<attributed.length {
            XCTAssertNil(
                attributed.attribute(.paragraphStyle, at: index, effectiveRange: nil),
                "no paragraph style should be written anywhere (index \(index))"
            )
        }
    }

    // MARK: - Interaction with renumbering

    /// The rewritten numeral inherits the marker's attributes, which now
    /// include the paragraph style — so a renumbered item keeps its spacing.
    func testRenumberedItemKeepsItsSpacing() {
        let attributed = MarkdownRenderer.render(markdown: "1. one\n1. two\n", style: style())
        let markerLocation = (attributed.string as NSString).range(of: "2.").location
        XCTAssertNotEqual(markerLocation, NSNotFound)

        let paragraphStyle = attributed.attribute(
            .paragraphStyle,
            at: markerLocation,
            effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.paragraphSpacingBefore, 6)
    }

    /// The whole point of using a paragraph attribute: the text is untouched.
    func testSpacingDoesNotAlterTheText() {
        let source = "- one\n- two\n\n1. a\n1. b\n"
        XCTAssertEqual(
            MarkdownRenderer.render(markdown: source, style: style(), renumberOrderedLists: false).string,
            source
        )
    }
}
