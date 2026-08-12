import AppKit
import XCTest
@testable import mdview

/// Ordered-list numerals are the one place mdview rewrites the source text
/// instead of only coloring it, so the exception gets its own suite: what it
/// changes, what it must leave alone, and that it can be switched off.
final class OrderedListNumberingTests: XCTestCase {
    private func style() -> MarkdownStyle {
        MarkdownStyle(
            theme: .default,
            bodyFontName: "Helvetica",
            bodyFontSize: 13,
            isDarkAppearance: false,
            boldHeadings: true
        )
    }

    private func rendered(_ markdown: String, renumber: Bool = true) -> String {
        MarkdownRenderer.render(
            markdown: markdown,
            style: style(),
            renumberOrderedLists: renumber
        ).string
    }

    // MARK: - Numbering

    /// The case this feature exists for: CommonMark ignores every numeral
    /// after the first, so a whole list written as "1." is valid markdown.
    func testLazyNumberingIsShownInSequence() {
        XCTAssertEqual(
            rendered("1. one\n1. two\n1. three\n"),
            "1. one\n2. two\n3. three\n"
        )
    }

    /// The first item sets where the list starts and is never rewritten.
    func testListStartingAtAnotherNumberCountsFromThere() {
        XCTAssertEqual(
            rendered("5. five\n5. six\n5. seven\n"),
            "5. five\n6. six\n7. seven\n"
        )
    }

    func testNestedListRestartsWhileTheParentKeepsCounting() {
        let source = """
        1. one
        1. two
           1. nested a
           1. nested b
        1. three

        """
        XCTAssertEqual(
            rendered(source),
            """
            1. one
            2. two
               1. nested a
               2. nested b
            3. three

            """
        )
    }

    /// Only the digits are replaced, so a list written with ")" stays a ")"
    /// list rather than being silently converted to ".".
    func testParenthesisDelimiterIsPreserved() {
        XCTAssertEqual(
            rendered("1) one\n1) two\n"),
            "1) one\n2) two\n"
        )
    }

    func testCorrectlyNumberedListIsLeftAlone() {
        let source = "1. one\n2. two\n3. three\n"
        XCTAssertEqual(rendered(source), source)
    }

    func testUnorderedListIsLeftAlone() {
        let source = "- one\n- two\n"
        XCTAssertEqual(rendered(source), source)
    }

    /// Nothing outside a list-item node is touched, so a numeral that happens
    /// to look like a marker inside a fenced block stays as written.
    func testNumeralInsideCodeBlockIsNotRewritten() {
        let source = "```\n1. not a list\n1. still not a list\n```\n"
        XCTAssertEqual(rendered(source), source)
    }

    // MARK: - Widening numerals

    /// Going from one digit to two lengthens the string mid-document, which is
    /// exactly what would corrupt the ranges recorded for everything after it.
    func testTwoDigitNumeralsDoNotShiftLaterHighlighting() {
        let items = String(repeating: "1. item\n", count: 12)
        let source = items + "\n# After the list\n"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: source, style: currentStyle)
        let text = attributed.string as NSString

        XCTAssertTrue(attributed.string.contains("10. item"))
        XCTAssertTrue(attributed.string.contains("12. item"))

        // The heading sits after four inserted characters; if the post-pass
        // corrupted the offsets, this range would carry body attributes.
        let headingLocation = text.range(of: "# After the list").location
        XCTAssertNotEqual(headingLocation, NSNotFound)
        let color = attributed.attribute(.foregroundColor, at: headingLocation, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, currentStyle.color(for: .heading1))
    }

    // MARK: - Attributes

    func testRenumberedMarkerKeepsTheListMarkerColor() {
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: "1. one\n1. two\n", style: currentStyle)
        let markerLocation = (attributed.string as NSString).range(of: "2.").location
        XCTAssertNotEqual(markerLocation, NSNotFound)

        let color = attributed.attribute(.foregroundColor, at: markerLocation, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, currentStyle.color(for: .listMarker))
    }

    func testWidenedMarkerKeepsTheListMarkerColorAcrossBothDigits() {
        let currentStyle = style()
        let source = String(repeating: "1. item\n", count: 10)
        let attributed = MarkdownRenderer.render(markdown: source, style: currentStyle)
        let markerLocation = (attributed.string as NSString).range(of: "10.").location
        XCTAssertNotEqual(markerLocation, NSNotFound)

        for offset in 0..<3 {
            let color = attributed.attribute(
                .foregroundColor,
                at: markerLocation + offset,
                effectiveRange: nil
            ) as? NSColor
            XCTAssertEqual(color, currentStyle.color(for: .listMarker), "character \(offset) of \"10.\"")
        }
    }

    // MARK: - Opting out

    func testRenumberingCanBeDisabledForAVerbatimView() {
        let source = "1. one\n1. two\n1. three\n"
        XCTAssertEqual(rendered(source, renumber: false), source)
    }
}
