import AppKit
import XCTest
@testable import mdview

/// Body text and code carry independent fonts. These pin the separation where
/// it is observable: the attributes on the rendered string.
final class FontSelectionTests: XCTestCase {
    private func style(
        body: String = "Georgia",
        bodySize: CGFloat = 13,
        code: String = "Menlo",
        codeSize: CGFloat = 13
    ) -> MarkdownStyle {
        MarkdownStyle(
            theme: .default,
            bodyFontName: body,
            bodyFontSize: bodySize,
            codeFontName: code,
            codeFontSize: codeSize,
            isDarkAppearance: false,
            boldHeadings: true
        )
    }

    private func font(in attributed: NSAttributedString, at substring: String) -> NSFont? {
        let location = (attributed.string as NSString).range(of: substring).location
        guard location != NSNotFound else { return nil }
        return attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    func testProseAndInlineCodeUseTheirOwnFamilies() throws {
        let text = "prose words and `code span` here"
        let attributed = MarkdownRenderer.render(markdown: text, style: style())

        XCTAssertEqual(try XCTUnwrap(font(in: attributed, at: "prose")).familyName, "Georgia")
        XCTAssertEqual(try XCTUnwrap(font(in: attributed, at: "code span")).familyName, "Menlo")
    }

    /// The sizes are independent, not one size with two families.
    func testFencedBlockUsesTheCodeFamilyAndItsOwnSize() throws {
        let text = "prose\n\n```\nlet x = 1\n```\n"
        let attributed = MarkdownRenderer.render(
            markdown: text,
            style: style(bodySize: 13, codeSize: 20)
        )

        let body = try XCTUnwrap(font(in: attributed, at: "prose"))
        let code = try XCTUnwrap(font(in: attributed, at: "let x = 1"))

        XCTAssertEqual(body.familyName, "Georgia")
        XCTAssertEqual(body.pointSize, 13)
        XCTAssertEqual(code.familyName, "Menlo")
        XCTAssertEqual(code.pointSize, 20)
    }

    /// Headings follow the body font, not the code one.
    func testHeadingUsesTheBodyFamily() throws {
        let attributed = MarkdownRenderer.render(markdown: "# Title\n", style: style())
        XCTAssertEqual(try XCTUnwrap(font(in: attributed, at: "Title")).familyName, "Georgia")
    }

    func testInlineCodeInsideBoldKeepsBoldAndTheCodeFamily() throws {
        let attributed = MarkdownRenderer.render(
            markdown: "**bold with `code` inside**\n",
            style: style()
        )
        let font = try XCTUnwrap(font(in: attributed, at: "code"))

        XCTAssertEqual(font.familyName, "Menlo")
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    /// An uninstalled family must still render code as code.
    func testUnavailableCodeFamilyFallsBackToTheSystemMonospacedFont() throws {
        let attributed = MarkdownRenderer.render(
            markdown: "a `span` b",
            style: style(code: "No Such Font Installed")
        )
        let font = try XCTUnwrap(font(in: attributed, at: "span"))

        XCTAssertEqual(font.fontName, NSFont.monospacedSystemFont(ofSize: 13, weight: .regular).fontName)
    }

    func testUnavailableBodyFamilyFallsBackToTheSystemFont() throws {
        let attributed = MarkdownRenderer.render(
            markdown: "plain words",
            style: style(body: "No Such Font Installed")
        )
        let font = try XCTUnwrap(font(in: attributed, at: "plain"))

        XCTAssertEqual(font.fontName, NSFont.systemFont(ofSize: 13).fontName)
    }
}
