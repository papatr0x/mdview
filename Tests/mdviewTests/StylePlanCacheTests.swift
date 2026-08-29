import AppKit
import XCTest
@testable import mdview

/// The plan/paint split exists so a preference change repaints without
/// re-parsing, and so the parse can run off the main thread. These assert the
/// split is *equivalent* — a cached plan must produce byte-for-byte what a
/// fresh full render produces — and that the cache hands a parsed plan back
/// synchronously afterwards.
@MainActor
final class StylePlanCacheTests: XCTestCase {
    private func style(size: CGFloat = 13, dark: Bool = false) -> MarkdownStyle {
        MarkdownStyle(
            theme: .default,
            bodyFontName: "Helvetica",
            bodyFontSize: size,
            codeFontName: "Menlo",
            codeFontSize: size,
            isDarkAppearance: dark,
            boldHeadings: true,
            listItemSpacing: 6
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

    func testCachedPlanRepaintsIdenticallyToAFullRender() async {
        let cache = StylePlanCache()
        let plan = await cache.plan(for: sample)

        for currentStyle in [style(), style(dark: true), style(size: 22)] {
            assertEquivalent(
                MarkdownRenderer.render(plan: plan, markdown: sample, style: currentStyle),
                MarkdownRenderer.render(markdown: sample, style: currentStyle)
            )
        }
    }

    /// The rewrites live in every plan and are applied or not at paint time,
    /// which is what lets the toggle flip without rebuilding anything.
    func testTogglingRenumberingReusesTheSamePlan() async {
        let cache = StylePlanCache()
        let plan = await cache.plan(for: sample)

        assertEquivalent(
            MarkdownRenderer.render(plan: plan, markdown: sample, style: style(), renumberOrderedLists: false),
            MarkdownRenderer.render(markdown: sample, style: style(), renumberOrderedLists: false)
        )
        assertEquivalent(
            MarkdownRenderer.render(plan: plan, markdown: sample, style: style(), renumberOrderedLists: true),
            MarkdownRenderer.render(markdown: sample, style: style(), renumberOrderedLists: true)
        )
    }

    func testCacheReturnsAFreshPlanWhenTheTextChanges() async {
        let cache = StylePlanCache()
        _ = await cache.plan(for: "# First")

        let other = "1. one\n1. two\n"
        let plan = await cache.plan(for: other)
        assertEquivalent(
            MarkdownRenderer.render(plan: plan, markdown: other, style: style()),
            MarkdownRenderer.render(markdown: other, style: style())
        )
        XCTAssertNil(cache.cachedPlan(for: "# First"),
                     "the cache holds one document, so the old plan is gone")
    }

    // MARK: - Parsing off the main thread

    /// The parse is awaited, but what it produces has to be available without
    /// awaiting again: that synchronous hit is the path every preference change
    /// takes, and the color wells are continuous, so a drag asks for it once per
    /// mouse event.
    func testAParsedPlanIsAvailableSynchronously() async throws {
        let cache = StylePlanCache()
        XCTAssertNil(cache.cachedPlan(for: sample), "nothing is parsed before it is asked for")

        _ = await cache.plan(for: sample)

        let cached = try XCTUnwrap(cache.cachedPlan(for: sample),
                                   "a finished parse must be reusable without suspending")
        assertEquivalent(
            MarkdownRenderer.render(plan: cached, markdown: sample, style: style()),
            MarkdownRenderer.render(markdown: sample, style: style())
        )
    }

    /// A settings change can arrive while the first parse is still running. Both
    /// callers wait on the one parse — there is a single pending slot — and both
    /// must come away with a plan that paints the same document.
    func testOverlappingRequestsForTheSameTextAgree() async {
        let cache = StylePlanCache()

        async let first = cache.plan(for: sample)
        async let second = cache.plan(for: sample)
        let (one, two) = await (first, second)

        assertEquivalent(
            MarkdownRenderer.render(plan: one, markdown: sample, style: style()),
            MarkdownRenderer.render(plan: two, markdown: sample, style: style())
        )
    }

    func testEmptyDocumentPlansAndPaintsWithoutTrapping() async {
        let cache = StylePlanCache()
        let plan = await cache.plan(for: "")
        let rendered = MarkdownRenderer.render(plan: plan, markdown: "", style: style())

        XCTAssertEqual(rendered.string, "")
    }
}
