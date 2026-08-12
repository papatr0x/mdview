import AppKit
import XCTest
@testable import mdview

/// The plan/paint split exists so a preference change repaints without
/// re-parsing. These assert the split is *equivalent* — a cached plan must
/// produce byte-for-byte what a fresh full render produces.
final class StylePlanCacheTests: XCTestCase {
    private func style(size: CGFloat = 13, dark: Bool = false) -> MarkdownStyle {
        MarkdownStyle(
            theme: .default,
            bodyFontName: "Helvetica",
            bodyFontSize: size,
            isDarkAppearance: dark,
            boldHeadings: true
        )
    }

    private var sample: String {
        """
        # Title

        Text with **bold**, *italic*, `code` and a [link](https://example.com).

        > quoted

        - dash item
        1. one
        1. two
           1. nested
           1. nested two

        ```
        let x = 1
        ```

        ---

        """
    }

    private func assertEquivalent(
        _ produced: NSAttributedString,
        _ expected: NSAttributedString,
        line: UInt = #line
    ) {
        XCTAssertEqual(produced.string, expected.string, "text differs", line: line)
        XCTAssertTrue(produced.isEqual(to: expected), "attributes differ", line: line)
    }

    func testCachedPlanRepaintsIdenticallyToAFullRender() {
        let cache = StylePlanCache()
        let plan = cache.plan(for: sample)

        for currentStyle in [style(), style(dark: true), style(size: 22)] {
            assertEquivalent(
                MarkdownRenderer.render(plan: plan, markdown: sample, style: currentStyle),
                MarkdownRenderer.render(markdown: sample, style: currentStyle)
            )
        }
    }

    /// The rewrites live in every plan and are applied or not at paint time,
    /// which is what lets the toggle flip without rebuilding anything.
    func testTogglingRenumberingReusesTheSamePlan() {
        let cache = StylePlanCache()
        let plan = cache.plan(for: sample)

        assertEquivalent(
            MarkdownRenderer.render(plan: plan, markdown: sample, style: style(), renumberOrderedLists: false),
            MarkdownRenderer.render(markdown: sample, style: style(), renumberOrderedLists: false)
        )
        assertEquivalent(
            MarkdownRenderer.render(plan: plan, markdown: sample, style: style(), renumberOrderedLists: true),
            MarkdownRenderer.render(markdown: sample, style: style(), renumberOrderedLists: true)
        )
    }

    func testCacheReturnsAFreshPlanWhenTheTextChanges() {
        let cache = StylePlanCache()
        _ = cache.plan(for: "# First")

        let other = "1. one\n1. two\n"
        assertEquivalent(
            MarkdownRenderer.render(plan: cache.plan(for: other), markdown: other, style: style()),
            MarkdownRenderer.render(markdown: other, style: style())
        )
    }

    func testEmptyDocumentPlansAndPaintsWithoutTrapping() {
        let cache = StylePlanCache()
        let rendered = MarkdownRenderer.render(plan: cache.plan(for: ""), markdown: "", style: style())

        XCTAssertEqual(rendered.string, "")
    }
}
