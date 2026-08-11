import AppKit
import Markdown

/// Renders markdown as **syntax-highlighted source**, not a WYSIWYG preview:
/// the original text (including `#`, `>`, `**`, backticks, etc.) is preserved
/// verbatim, and colors/traits are layered on top of it per node type. This
/// mirrors how a code editor colorizes source rather than how a browser
/// renders HTML.
enum MarkdownRenderer {
    static func render(markdown text: String, style: MarkdownStyle) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: style.font(for: .body),
                .foregroundColor: style.color(for: .body)
            ]
        )
        guard !text.isEmpty else { return attributed }

        let document = Document(parsing: text)
        var highlighter = SourceHighlighter(
            text: text,
            lineStartUTF8Offsets: Self.lineStartUTF8Offsets(in: text),
            style: style,
            attributed: attributed
        )
        highlighter.visit(document)
        return highlighter.attributed
    }

    private static func lineStartUTF8Offsets(in text: String) -> [Int] {
        var offsets = [0]
        var count = 0
        for byte in text.utf8 {
            count += 1
            if byte == UInt8(ascii: "\n") {
                offsets.append(count)
            }
        }
        return offsets
    }
}

private struct SourceHighlighter: MarkupVisitor {
    typealias Result = Void

    let text: String
    let lineStartUTF8Offsets: [Int]
    let style: MarkdownStyle
    var attributed: NSMutableAttributedString

    // MARK: - Leaf / whole-range coloring

    mutating func defaultVisit(_ markup: Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    mutating func visitHeading(_ heading: Heading) {
        if let range = nsRange(for: heading) {
            apply(kind: headingKind(for: heading.level), range: range)
        }
        for child in heading.children { visit(child) }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if let range = nsRange(for: blockQuote) {
            apply(kind: .blockquote, range: range, changeFont: false)
        }
        for child in blockQuote.children { visit(child) }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if let range = nsRange(for: codeBlock) {
            apply(kind: .codeBlock, range: range)
            // Coloring through each line's trailing newline is what makes
            // NSTextView stretch the background to the full line width,
            // giving the fenced block its solid "block" look.
            attributed.addAttribute(.backgroundColor, value: style.codeBlockBackgroundColor, range: range)
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        if let range = nsRange(for: thematicBreak) {
            apply(kind: .thematicBreak, range: range, changeFont: false)
        }
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        if let range = nsRange(for: inlineCode) {
            apply(kind: .inlineCode, range: range, changeFont: false)
            // Enclosing strong/emphasis nodes are visited first, so the range
            // may already carry bold/italic; switch to monospaced without
            // discarding those traits.
            applyMonospacedPreservingTraits(kind: .inlineCode, range: range)
        }
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = nsRange(for: strong) {
            apply(kind: .strong, range: range, changeFont: false)
            addTrait(bold: true, italic: false, range: range)
        }
        for child in strong.children { visit(child) }
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = nsRange(for: emphasis) {
            apply(kind: .emphasis, range: range, changeFont: false)
            addTrait(bold: false, italic: true, range: range)
        }
        for child in emphasis.children { visit(child) }
    }

    mutating func visitLink(_ link: Link) {
        if let range = nsRange(for: link) {
            apply(kind: .link, range: range, changeFont: false)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        for child in link.children { visit(child) }
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let full = nsRange(for: listItem), let markerRange = markerRange(within: full) {
            apply(kind: .listMarker, range: markerRange, changeFont: false)
        }
        for child in listItem.children { visit(child) }
    }

    // MARK: - Attribute application

    private mutating func apply(kind: MarkdownNodeKind, range: NSRange, changeFont: Bool = true) {
        attributed.addAttribute(.foregroundColor, value: style.color(for: kind), range: range)
        if changeFont {
            attributed.addAttribute(.font, value: style.font(for: kind), range: range)
        }
    }

    private mutating func applyMonospacedPreservingTraits(kind: MarkdownNodeKind, range: NSRange) {
        let monoFont = style.font(for: kind)
        attributed.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let existingTraits = (value as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let newFont = style.withTraits(
                monoFont,
                bold: existingTraits.contains(.boldFontMask),
                italic: existingTraits.contains(.italicFontMask)
            )
            attributed.addAttribute(.font, value: newFont, range: subRange)
        }
    }

    private mutating func addTrait(bold: Bool, italic: Bool, range: NSRange) {
        attributed.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let currentFont = (value as? NSFont) ?? style.baseFont
            let newFont = style.withTraits(currentFont, bold: bold, italic: italic)
            attributed.addAttribute(.font, value: newFont, range: subRange)
        }
    }

    /// The list marker ("-", "*", "+", or "1.") always sits at the very start
    /// of a list item's source range, and is followed by whitespace. Color
    /// only the marker itself: stop at the first whitespace character of any
    /// kind (a tab is as valid a separator as a space) and leave that
    /// separator out of the returned range.
    private func markerRange(within itemRange: NSRange) -> NSRange? {
        let nsText = attributed.string as NSString
        guard itemRange.location != NSNotFound, itemRange.length > 0 else { return nil }
        let searchLength = min(itemRange.length, 8)
        let prefix = nsText.substring(with: NSRange(location: itemRange.location, length: searchLength))
        var markerLength = 0
        for character in prefix {
            if character.isWhitespace { break }
            markerLength += String(character).utf16.count
        }
        guard markerLength > 0 else { return nil }
        return NSRange(location: itemRange.location, length: markerLength)
    }

    private func headingKind(for level: Int) -> MarkdownNodeKind {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        default: return .heading6
        }
    }

    // MARK: - Source range mapping

    private func nsRange(for markup: Markup) -> NSRange? {
        guard let range = markup.range else { return nil }
        guard let start = utf8Offset(line: range.lowerBound.line, column: range.lowerBound.column),
              let end = utf8Offset(line: range.upperBound.line, column: range.upperBound.column),
              start <= end else { return nil }
        guard let startIndex = stringIndex(forUTF8Offset: start),
              let endIndex = stringIndex(forUTF8Offset: end),
              startIndex <= endIndex else { return nil }
        return NSRange(startIndex..<endIndex, in: text)
    }

    private func utf8Offset(line: Int, column: Int) -> Int? {
        guard line >= 1, line <= lineStartUTF8Offsets.count else { return nil }
        return lineStartUTF8Offsets[line - 1] + (column - 1)
    }

    private func stringIndex(forUTF8Offset offset: Int) -> String.Index? {
        guard offset >= 0,
              let utf8Index = text.utf8.index(
                text.utf8.startIndex,
                offsetBy: offset,
                limitedBy: text.utf8.endIndex
              ) else { return nil }
        return utf8Index.samePosition(in: text)
    }
}
