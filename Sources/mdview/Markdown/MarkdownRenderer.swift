import AppKit
import Markdown

/// What the source says, independent of how it should look: the ranges to
/// style, what each one is, and any ordered-list numerals to rewrite.
///
/// This is the expensive half of rendering and it depends only on the text —
/// parsing, walking the tree, and mapping every node's line/column range to an
/// `NSRange`. Changing a color or the font size does not change any of it, so
/// a plan is built once per document and replayed against whatever
/// `MarkdownStyle` is current (see `StylePlanCache`).
struct StylePlan {
    fileprivate let operations: [StyleOperation]
    fileprivate let renumberings: [Renumbering]
}

/// Renders markdown as **syntax-highlighted source**, not a WYSIWYG preview:
/// the original text (including `#`, `>`, `**`, backticks, etc.) is preserved
/// verbatim, and colors/traits are layered on top of it per node type. This
/// mirrors how a code editor colorizes source rather than how a browser
/// renders HTML.
///
/// Ordered-list numerals are the one deliberate exception — see
/// `renumberOrderedLists`.
enum MarkdownRenderer {
    /// Parses `text` and works out what to style, without deciding any colors.
    static func plan(for text: String) -> StylePlan {
        guard !text.isEmpty else { return StylePlan(operations: [], renumberings: []) }

        var planner = SourcePlanner(
            text: text,
            lineStartUTF8Offsets: Self.lineStartUTF8Offsets(in: text)
        )
        planner.visit(Document(parsing: text))
        return StylePlan(operations: planner.operations, renumberings: planner.renumberings)
    }

    /// Paints a plan with a concrete style. Cheap enough to redo on every
    /// preference change, which is the point of separating it from `plan(for:)`.
    ///
    /// - Parameter renumberOrderedLists: Displays each ordered-list item with
    ///   its actual position instead of the numeral written in the file.
    ///   CommonMark only reads the *first* item's number (it sets where the
    ///   list starts) and ignores every one after it, so a list written
    ///   entirely as `1.` is both perfectly valid and unreadable as a list.
    ///   This is the only place mdview alters the source text; the "Renumber
    ///   ordered lists" setting turns it off for a strictly verbatim view.
    ///   The rewrites are part of every plan — they depend on the text, not on
    ///   the style — so toggling the setting does not invalidate a cached plan.
    static func render(
        plan: StylePlan,
        markdown text: String,
        style: MarkdownStyle,
        renumberOrderedLists: Bool = true
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: style.font(for: .body),
                .foregroundColor: style.color(for: .body)
            ]
        )
        for operation in plan.operations {
            Self.apply(operation, to: attributed, style: style)
        }
        if renumberOrderedLists {
            Self.apply(plan.renumberings, to: attributed)
        }
        return attributed
    }

    /// Plan and paint in one go, for callers with nothing to cache.
    static func render(
        markdown text: String,
        style: MarkdownStyle,
        renumberOrderedLists: Bool = true
    ) -> NSAttributedString {
        render(
            plan: plan(for: text),
            markdown: text,
            style: style,
            renumberOrderedLists: renumberOrderedLists
        )
    }

    // MARK: - Painting

    /// The operations are replayed in the order the walk produced them, which
    /// several of them depend on: `.monospacedPreservingTraits` and `.trait`
    /// read the font already sitting on the range and build on it, so an
    /// enclosing bold must have been applied before the inline code inside it.
    private static func apply(
        _ operation: StyleOperation,
        to attributed: NSMutableAttributedString,
        style: MarkdownStyle
    ) {
        switch operation {
        case let .style(kind, range, changeFont):
            attributed.addAttribute(.foregroundColor, value: style.color(for: kind), range: range)
            if changeFont {
                attributed.addAttribute(.font, value: style.font(for: kind), range: range)
            }

        case let .codeBlockBackground(range):
            // Coloring through each line's trailing newline is what makes
            // NSTextView stretch the background to the full line width,
            // giving the fenced block its solid "block" look.
            attributed.addAttribute(.backgroundColor, value: style.codeBlockBackgroundColor, range: range)

        case let .underline(range):
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)

        case let .trait(bold, italic, range):
            attributed.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let currentFont = (value as? NSFont) ?? style.baseFont
                attributed.addAttribute(
                    .font,
                    value: style.withTraits(currentFont, bold: bold, italic: italic),
                    range: subRange
                )
            }

        case let .monospacedPreservingTraits(kind, range):
            // Enclosing strong/emphasis nodes are painted first, so the range
            // may already carry bold/italic; switch to monospaced without
            // discarding those traits.
            let monoFont = style.font(for: kind)
            attributed.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let existingTraits = (value as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
                attributed.addAttribute(
                    .font,
                    value: style.withTraits(
                        monoFont,
                        bold: existingTraits.contains(.boldFontMask),
                        italic: existingTraits.contains(.italicFontMask)
                    ),
                    range: subRange
                )
            }
        }
    }

    /// Rewriting a numeral changes the string's length, which would invalidate
    /// every range the plan recorded against the *original* text. Applying the
    /// edits back to front — after everything else, never during it — means
    /// each range is still accurate at the moment it is used, since an edit
    /// only shifts the text that follows it.
    private static func apply(_ renumberings: [Renumbering], to attributed: NSMutableAttributedString) {
        for renumbering in renumberings.sorted(by: { $0.range.location > $1.range.location }) {
            guard NSMaxRange(renumbering.range) <= attributed.length else { continue }
            // The replacement inherits the marker's own attributes, so the new
            // digits keep the list-marker color and font already resolved.
            let attributes = attributed.attributes(at: renumbering.range.location, effectiveRange: nil)
            attributed.replaceCharacters(
                in: renumbering.range,
                with: NSAttributedString(string: renumbering.replacement, attributes: attributes)
            )
        }
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

/// One styling decision, recorded without resolving it: which range, and what
/// to do to it. Colors and fonts come later, from whatever style is current.
private enum StyleOperation {
    case style(kind: MarkdownNodeKind, range: NSRange, changeFont: Bool)
    case codeBlockBackground(NSRange)
    case underline(NSRange)
    case trait(bold: Bool, italic: Bool, range: NSRange)
    case monospacedPreservingTraits(kind: MarkdownNodeKind, range: NSRange)
}

/// A pending rewrite of one ordered-list numeral: the range of the digits as
/// they appear in the source, and the number to show in their place.
private struct Renumbering {
    let range: NSRange
    let replacement: String
}

/// Walks the parsed document and records what should be styled, never how.
private struct SourcePlanner: MarkupVisitor {
    typealias Result = Void

    let text: String
    let lineStartUTF8Offsets: [Int]

    var operations: [StyleOperation] = []
    var renumberings: [Renumbering] = []

    private var nsText: NSString { text as NSString }

    // MARK: - Leaf / whole-range coloring

    mutating func defaultVisit(_ markup: Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    mutating func visitHeading(_ heading: Heading) {
        if let range = nsRange(for: heading) {
            operations.append(.style(kind: headingKind(for: heading.level), range: range, changeFont: true))
        }
        for child in heading.children { visit(child) }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if let range = nsRange(for: blockQuote) {
            operations.append(.style(kind: .blockquote, range: range, changeFont: false))
        }
        for child in blockQuote.children { visit(child) }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if let range = nsRange(for: codeBlock) {
            operations.append(.style(kind: .codeBlock, range: range, changeFont: true))
            operations.append(.codeBlockBackground(range))
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        if let range = nsRange(for: thematicBreak) {
            operations.append(.style(kind: .thematicBreak, range: range, changeFont: false))
        }
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        if let range = nsRange(for: inlineCode) {
            operations.append(.style(kind: .inlineCode, range: range, changeFont: false))
            operations.append(.monospacedPreservingTraits(kind: .inlineCode, range: range))
        }
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = nsRange(for: strong) {
            operations.append(.style(kind: .strong, range: range, changeFont: false))
            operations.append(.trait(bold: true, italic: false, range: range))
        }
        for child in strong.children { visit(child) }
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = nsRange(for: emphasis) {
            operations.append(.style(kind: .emphasis, range: range, changeFont: false))
            operations.append(.trait(bold: false, italic: true, range: range))
        }
        for child in emphasis.children { visit(child) }
    }

    mutating func visitLink(_ link: Link) {
        if let range = nsRange(for: link) {
            operations.append(.style(kind: .link, range: range, changeFont: false))
            operations.append(.underline(range))
        }
        for child in link.children { visit(child) }
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let full = nsRange(for: listItem), let markerRange = markerRange(within: full) {
            operations.append(.style(kind: .listMarker, range: markerRange, changeFont: false))
        }
        for child in listItem.children { visit(child) }
    }

    /// Each `OrderedList` node carries its own counter, so a nested list
    /// restarts rather than continuing its parent's numbering.
    mutating func visitOrderedList(_ orderedList: OrderedList) {
        // CommonMark takes the start from the first item's numeral and ignores
        // the rest, which is exactly the rule being made visible here.
        var number = orderedList.startIndex
        for item in orderedList.listItems {
            recordRenumbering(of: item, to: number)
            number += 1
            visit(item)
        }
    }

    // MARK: - Ordered-list numerals

    private mutating func recordRenumbering(of listItem: ListItem, to number: UInt) {
        guard let itemRange = nsRange(for: listItem),
              let digits = digitsRange(atStartOf: itemRange) else { return }
        let replacement = String(number)
        guard nsText.substring(with: digits) != replacement else { return }
        renumberings.append(Renumbering(range: digits, replacement: replacement))
    }

    /// The digits of an ordered marker, without the `.`/`)` that follows them —
    /// leaving the delimiter alone is what keeps a `1)` list numbered `2)`
    /// rather than silently converted to `2.`.
    ///
    /// Returns nil unless the item really does start with digits followed by a
    /// delimiter: text this function does not positively recognize is never
    /// rewritten.
    private func digitsRange(atStartOf itemRange: NSRange) -> NSRange? {
        guard itemRange.location != NSNotFound, itemRange.length > 0 else { return nil }
        // One past the nine digits CommonMark allows is enough to see that a
        // longer run is not a marker at all.
        let limit = min(itemRange.length, Self.longestOrderedMarkerLength)
        var length = 0
        while length < limit, isASCIIDigit(nsText.character(at: itemRange.location + length)) {
            length += 1
        }
        guard length > 0, length < itemRange.length else { return nil }
        let delimiter = nsText.character(at: itemRange.location + length)
        guard delimiter == Self.utf16(".") || delimiter == Self.utf16(")") else { return nil }
        return NSRange(location: itemRange.location, length: length)
    }

    /// Nine digits — CommonMark's limit for an ordered-list marker — plus the
    /// `.` or `)` that closes it.
    private static let longestOrderedMarkerLength = 10

    private func isASCIIDigit(_ character: unichar) -> Bool {
        character >= Self.utf16("0") && character <= Self.utf16("9")
    }

    private static func utf16(_ character: Unicode.Scalar) -> unichar {
        unichar(UInt8(ascii: character))
    }

    // MARK: - Marker range

    /// The list marker ("-", "*", "+", or "1.") always sits at the very start
    /// of a list item's source range, and is followed by whitespace. Color
    /// only the marker itself: stop at the first whitespace character of any
    /// kind (a tab is as valid a separator as a space) and leave that
    /// separator out of the returned range.
    ///
    /// The scan window is the longest marker CommonMark allows: nine digits
    /// plus a delimiter. A shorter window left the tail of a long marker
    /// uncolored — and renumbering made that visible *within one document*,
    /// since a rewritten numeral inherits the marker attributes wholesale
    /// while an untouched one kept the truncation.
    private func markerRange(within itemRange: NSRange) -> NSRange? {
        guard itemRange.location != NSNotFound, itemRange.length > 0 else { return nil }
        let searchLength = min(itemRange.length, Self.longestOrderedMarkerLength)
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
