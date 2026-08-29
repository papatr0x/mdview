import AppKit
import XCTest
@testable import mdview

final class MarkdownRendererTests: XCTestCase {
    private func style(dark: Bool = false, boldHeadings: Bool = true) -> MarkdownStyle {
        MarkdownStyle(
            theme: .default,
            bodyFontName: "Helvetica",
            bodyFontSize: 13,
            codeFontName: "Menlo",
            codeFontSize: 13,
            isDarkAppearance: dark,
            boldHeadings: boldHeadings,
            listItemSpacing: 4
        )
    }

    private var sampleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MarkdownRendererTests.swift
            .deletingLastPathComponent() // mdviewTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures/sample.md")
    }

    private func index(of substring: String, in text: String) -> Int {
        text.distance(from: text.startIndex, to: text.range(of: substring)!.lowerBound)
    }

    func testHeadingIsBoldAndColored() {
        let text = "# Title"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)

        let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, currentStyle.color(for: .heading1))

        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testHeadingBoldnessCanBeDisabled() {
        let text = "# Title"
        let currentStyle = style(boldHeadings: false)
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)

        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertFalse(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? true)
    }

    func testStrongTextIsBoldAndColored() {
        let text = "plain **bold** text"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)
        let idx = index(of: "bold", in: text)

        let font = attributed.attribute(.font, at: idx, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)

        let color = attributed.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, currentStyle.color(for: .strong))
    }

    func testEmphasisTextIsItalicAndColored() {
        let text = "plain *italic* text"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)
        let idx = index(of: "italic", in: text)

        let font = attributed.attribute(.font, at: idx, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false)

        let color = attributed.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, currentStyle.color(for: .emphasis))
    }

    func testBlockquoteIsColored() {
        let text = "> quoted text"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)
        let idx = index(of: "quoted", in: text)

        let color = attributed.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, currentStyle.color(for: .blockquote))
    }

    func testInlineCodeIsMonospacedAndColored() {
        let text = "run `code()` now"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)
        let idx = index(of: "code()", in: text)

        let font = attributed.attribute(.font, at: idx, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.familyName, "Menlo", "inline code uses the configured code font")
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false)

        let color = attributed.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, currentStyle.color(for: .inlineCode))
    }

    func testLinkIsUnderlinedAndColored() {
        let text = "see [this link](https://example.com) here"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)
        let idx = index(of: "this link", in: text)

        let color = attributed.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, currentStyle.color(for: .link))

        let underline = attributed.attribute(.underlineStyle, at: idx, effectiveRange: nil) as? Int
        XCTAssertEqual(underline, NSUnderlineStyle.single.rawValue)
    }

    func testFencedCodeBlockHasBackgroundColor() {
        let text = "before\n\n```\nlet x = 1\n```\n\nafter"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)
        let idx = index(of: "let x = 1", in: text)

        let background = attributed.attribute(.backgroundColor, at: idx, effectiveRange: nil) as? NSColor
        XCTAssertEqual(background, currentStyle.codeBlockBackgroundColor)

        // The fence delimiters themselves should also get the background.
        let fenceIdx = index(of: "```", in: text)
        let fenceBackground = attributed.attribute(.backgroundColor, at: fenceIdx, effectiveRange: nil) as? NSColor
        XCTAssertEqual(fenceBackground, currentStyle.codeBlockBackgroundColor)
    }

    func testFencedCodeBlockBackgroundCoversLineBreaksForBlockLook() {
        // Coloring through each line's trailing newline is what makes
        // NSTextView stretch the background to the full line width, giving
        // the fenced block its solid "block" look.
        let text = "```\nlet x = 1\n```\n"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)
        let nsText = attributed.string as NSString

        let lineEndIdx = nsText.range(of: "let x = 1").location + nsText.range(of: "let x = 1").length
        XCTAssertEqual(nsText.substring(with: NSRange(location: lineEndIdx, length: 1)), "\n")

        let newlineBackground = attributed.attribute(.backgroundColor, at: lineEndIdx, effectiveRange: nil) as? NSColor
        XCTAssertEqual(newlineBackground, currentStyle.codeBlockBackgroundColor)
    }

    func testListMarkerIsColored() {
        let text = "- item one"
        let currentStyle = style()
        let attributed = MarkdownRenderer.render(markdown: text, style: currentStyle)

        let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, currentStyle.color(for: .listMarker))
    }

    func testDarkPaletteAppliesDifferentColors() {
        let text = "# Title"
        let lightStyle = style(dark: false)
        let darkStyle = style(dark: true)

        let lightAttributed = MarkdownRenderer.render(markdown: text, style: lightStyle)
        let darkAttributed = MarkdownRenderer.render(markdown: text, style: darkStyle)

        let lightColor = lightAttributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let darkColor = darkAttributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

        XCTAssertNotEqual(lightColor, darkColor)
    }

    /// Rendered with ordered-list renumbering off, so this asserts the core
    /// invariant — highlighting alone never rewrites text — rather than
    /// relying on the fixture's list happening to be numbered correctly.
    /// Renumbering, the one sanctioned exception, is covered by
    /// `OrderedListNumberingTests`.
    func testRenderingPreservesOriginalSourceTextVerbatim() {
        let text = (try? String(contentsOf: sampleURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(text.isEmpty, "sample.md fixture should be readable")

        let attributed = MarkdownRenderer.render(
            markdown: text,
            style: style(),
            renumberOrderedLists: false
        )
        XCTAssertEqual(attributed.string, text, "highlighting must not alter the source text")
    }
}
