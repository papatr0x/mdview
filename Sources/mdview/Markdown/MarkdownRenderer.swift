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
///
/// `Sendable` because it is built on a background thread and handed to the main
/// one: it is all value types, and it carries no resolved color or font — only
/// what the source says.
struct StylePlan: Sendable {
    fileprivate let operations: [StyleOperation]
    fileprivate let renumberings: [Renumbering]
    fileprivate let hiddenDelimiters: [NSRange]
}

/// Renders markdown as **syntax-highlighted source**, not a WYSIWYG preview:
/// the original text (including `#`, `>`, `**`, backticks, etc.) is preserved
/// verbatim, and colors/traits are layered on top of it per node type. This
/// mirrors how a code editor colorizes source rather than how a browser
/// renders HTML.
///
/// Ordered-list numerals are the one deliberate exception — see
/// `renumberOrderedLists`.
extension NSAttributedString.Key {
    /// Marks the `**`/`*`/`_` around emphasis and the backticks around inline
    /// code. It carries no
    /// appearance of its own: `AppearanceAwareTextView` reads it while
    /// generating glyphs and gives those characters no glyph at all, which is
    /// what hides them without touching a single character of the source.
    static let hiddenMarkdownDelimiter = NSAttributedString.Key("mdviewHiddenMarkdownDelimiter")

    /// How deeply nested the blockquote on this range is, so the text view can
    /// draw one rule down its left edge per level.
    static let blockquoteLevel = NSAttributedString.Key("mdviewBlockquoteLevel")
}

enum MarkdownRenderer {
    /// Parses `text` and works out what to style, without deciding any colors.
    static func plan(for text: String) -> StylePlan {
        guard !text.isEmpty else {
            return StylePlan(operations: [], renumberings: [], hiddenDelimiters: [])
        }

        var planner = SourcePlanner(
            text: text,
            lineStartUTF8Offsets: Self.lineStartUTF8Offsets(in: text)
        )
        planner.visit(Document(parsing: text))
        return StylePlan(
            operations: planner.operations,
            renumberings: planner.renumberings,
            hiddenDelimiters: planner.hiddenDelimiters
        )
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
    /// - Parameter hideMarkdownMarkers: Leaves the markup undrawn — the `**`,
    ///   `*` and `_` around emphasis, the backticks around inline code, the `#`
    ///   opening a heading and the `>` opening each line of a quote — so the
    ///   markup reads as what it marks instead of competing with its own
    ///   markers, which is what it did while a node's style covered its whole
    ///   range and rendered them bold, or as code, too. Unlike
    ///   the renumbering above, this alters no text: the marked characters stay
    ///   in the string and are dropped at glyph generation, so the document is
    ///   still the file and copying still yields the markers.
    static func render(
        plan: StylePlan,
        markdown text: String,
        style: MarkdownStyle,
        renumberOrderedLists: Bool = true,
        hideMarkdownMarkers: Bool = true
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
        if hideMarkdownMarkers {
            // Nothing is written when the setting is off, so switching it back
            // restores exactly the attributed string that came before it.
            for range in plan.hiddenDelimiters {
                attributed.addAttribute(.hiddenMarkdownDelimiter, value: true, range: range)
            }
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
        renumberOrderedLists: Bool = true,
        hideMarkdownMarkers: Bool = true
    ) -> NSAttributedString {
        render(
            plan: plan(for: text),
            markdown: text,
            style: style,
            renumberOrderedLists: renumberOrderedLists,
            hideMarkdownMarkers: hideMarkdownMarkers
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

        case let .listItemSpacing(range):
            // Nothing is written when the setting is zero, so turning the
            // spacing off restores exactly the previous attributed string.
            guard style.listItemSpacing > 0 else { break }
            Self.mutateParagraphStyle(of: attributed, in: range) { paragraphStyle in
                paragraphStyle.paragraphSpacingBefore = style.listItemSpacing
            }

        case let .headingFont(level, range):
            // Font only. Headings carry no colour of their own, so the body
            // colour the string was seeded with shows through.
            attributed.addAttribute(.font, value: style.headingFont(level: level), range: range)

        case let .blockquoteIndent(level, range):
            let indent = MarkdownStyle.blockquoteIndent * CGFloat(level)
            Self.mutateParagraphStyle(of: attributed, in: range) { paragraphStyle in
                // Both, or only the first line of each paragraph moves.
                paragraphStyle.firstLineHeadIndent = indent
                paragraphStyle.headIndent = indent
            }
            attributed.addAttribute(.blockquoteLevel, value: level, range: range)

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

    /// Adds to whatever paragraph style is already on the range instead of
    /// replacing it.
    ///
    /// `addAttribute(.paragraphStyle:)` swaps the whole object, so two
    /// paragraph-level attributes cancel each other out depending on which ran
    /// last — and there are two now: a blockquote's indent and a list item's
    /// spacing, which meet whenever a list sits inside a quote. Copying and
    /// mutating costs an allocation per range, which is the price of the two
    /// composing at all.
    private static func mutateParagraphStyle(
        of attributed: NSMutableAttributedString,
        in range: NSRange,
        _ change: (NSMutableParagraphStyle) -> Void
    ) {
        guard range.length > 0 else { return }
        attributed.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
            let existing = (value as? NSParagraphStyle) ?? .default
            guard let updated = existing.mutableCopy() as? NSMutableParagraphStyle else { return }
            change(updated)
            attributed.addAttribute(.paragraphStyle, value: updated, range: subRange)
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

    /// Where every line begins, in UTF-8 bytes — the table that turns the
    /// parser's line/column positions back into offsets in the source.
    ///
    /// All three endings count, the same three the parser recognizes: LF, CRLF,
    /// and a lone CR. Counting only LF left a CR-terminated file looking like a
    /// single enormous line, so every position the parser reported past the
    /// first line fell outside the table and its node went unstyled — the whole
    /// document rendering as flat body text, with no error to show for it.
    private static func lineStartUTF8Offsets(in text: String) -> [Int] {
        var offsets = [0]
        var count = 0
        var previousByteWasCarriageReturn = false
        for byte in text.utf8 {
            count += 1
            if byte == UInt8(ascii: "\n") {
                if previousByteWasCarriageReturn {
                    // CRLF is one ending, not two: correct the start the CR
                    // just recorded rather than adding an empty line.
                    offsets[offsets.count - 1] = count
                } else {
                    offsets.append(count)
                }
                previousByteWasCarriageReturn = false
            } else if byte == UInt8(ascii: "\r") {
                offsets.append(count)
                previousByteWasCarriageReturn = true
            } else {
                previousByteWasCarriageReturn = false
            }
        }
        return offsets
    }
}

/// One styling decision, recorded without resolving it: which range, and what
/// to do to it. Colors and fonts come later, from whatever style is current.
private enum StyleOperation: Sendable {
    case style(kind: MarkdownNodeKind, range: NSRange, changeFont: Bool)
    case codeBlockBackground(NSRange)
    case underline(NSRange)
    case trait(bold: Bool, italic: Bool, range: NSRange)
    case monospacedPreservingTraits(kind: MarkdownNodeKind, range: NSRange)
    /// Carries no amount: how much space a list item gets is a setting, so it
    /// is resolved when painting, not when planning.
    case listItemSpacing(NSRange)
    /// A heading's size comes from its level and the body size, so only the
    /// level is recorded here.
    case headingFont(level: Int, range: NSRange)
    case blockquoteIndent(level: Int, range: NSRange)
}

/// A pending rewrite of one ordered-list numeral: the range of the digits as
/// they appear in the source, and the number to show in their place.
private struct Renumbering: Sendable {
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
    var hiddenDelimiters: [NSRange] = []
    var blockQuoteDepth = 0

    private var nsText: NSString { text as NSString }

    // MARK: - Leaf / whole-range coloring

    mutating func defaultVisit(_ markup: Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    mutating func visitHeading(_ heading: Heading) {
        if let range = nsRange(for: heading) {
            operations.append(.headingFont(level: heading.level, range: range))
            recordHeadingMarkers(in: range)
        }
        for child in heading.children { visit(child) }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        blockQuoteDepth += 1
        if let range = nsRange(for: blockQuote) {
            operations.append(.style(kind: .blockquote, range: range, changeFont: false))
            operations.append(.blockquoteIndent(level: blockQuoteDepth, range: range))
            recordBlockquoteMarkers(in: range)
        }
        for child in blockQuote.children { visit(child) }
        blockQuoteDepth -= 1
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
            // A span may be fenced by any number of backticks, so the run is
            // measured here the same way it is for emphasis.
            recordDelimiters(of: range, minimumWidth: 1)
        }
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = nsRange(for: strong) {
            operations.append(.style(kind: .strong, range: range, changeFont: false))
            operations.append(.trait(bold: true, italic: false, range: range))
            recordDelimiters(of: range, minimumWidth: 2)
        }
        for child in strong.children { visit(child) }
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = nsRange(for: emphasis) {
            operations.append(.style(kind: .emphasis, range: range, changeFont: false))
            operations.append(.trait(bold: false, italic: true, range: range))
            recordDelimiters(of: range, minimumWidth: 1)
        }
        for child in emphasis.children { visit(child) }
    }

    // MARK: - Block markers

    /// The `#` run that opens an ATX heading and the spaces after it — leaving
    /// those behind would push the title in by a space — plus the closing run
    /// CommonMark allows at the end of the line (`## Title ##`).
    ///
    /// A setext heading, underlined with `===` or `---`, has no `#` to hide;
    /// the guard on the first character leaves it alone.
    private mutating func recordHeadingMarkers(in range: NSRange) {
        guard range.location != NSNotFound, range.length > 0,
              NSMaxRange(range) <= nsText.length,
              nsText.character(at: range.location) == Self.utf16("#") else { return }

        var opening = 0
        while opening < range.length,
              nsText.character(at: range.location + opening) == Self.utf16("#") { opening += 1 }
        while opening < range.length,
              isSpaceOrTab(nsText.character(at: range.location + opening)) { opening += 1 }
        hiddenDelimiters.append(NSRange(location: range.location, length: opening))

        // The closing run is looked for *past* the node, out to the end of the
        // line: cmark strips it before reporting the range, so `## Title ##`
        // comes back covering only `## Title`. Staying inside the node — which
        // is where the opening run lives — would never have found it.
        let line = nsText.paragraphRange(for: NSRange(location: range.location, length: 0))
        let contentEnd = NSMaxRange(range)
        guard NSMaxRange(line) > contentEnd else { return }

        var cursor = NSMaxRange(line)
        while cursor > contentEnd, isLineTrailing(nsText.character(at: cursor - 1)) { cursor -= 1 }
        let hashesEnd = cursor
        while cursor > contentEnd, nsText.character(at: cursor - 1) == Self.utf16("#") { cursor -= 1 }
        guard cursor < hashesEnd else { return }

        // Everything between the title and the run has to be whitespace for
        // this to be a closing sequence rather than something else entirely.
        while cursor > contentEnd, isSpaceOrTab(nsText.character(at: cursor - 1)) { cursor -= 1 }
        guard cursor == contentEnd else { return }
        hiddenDelimiters.append(NSRange(location: cursor, length: hashesEnd - cursor))
    }

    /// The `>` opening every line of a quote, with the space after it, for as
    /// many levels as the line carries.
    ///
    /// Per line, because that is where the marker lives: a quote repeats it on
    /// each of its lines rather than only the first. One pass over the
    /// outermost quote already covers the inner markers of a nested one, so the
    /// inner node re-marks a subset — harmless, since the attribute says only
    /// that a character is a marker.
    private mutating func recordBlockquoteMarkers(in range: NSRange) {
        guard range.location != NSNotFound, range.length > 0,
              NSMaxRange(range) <= nsText.length else { return }

        var lineStart = nsText.paragraphRange(for: NSRange(location: range.location, length: 0)).location
        while lineStart < NSMaxRange(range) {
            let line = nsText.paragraphRange(for: NSRange(location: lineStart, length: 0))
            guard line.length > 0 else { return }
            markQuotePrefix(of: line)
            lineStart = NSMaxRange(line)
        }
    }

    private mutating func markQuotePrefix(of line: NSRange) {
        var cursor = line.location
        let end = NSMaxRange(line)
        while cursor < end {
            var scan = cursor
            while scan < end, isSpaceOrTab(nsText.character(at: scan)) { scan += 1 }
            // A line with no marker is a lazy continuation, and there is
            // nothing on it to hide.
            guard scan < end, nsText.character(at: scan) == Self.utf16(">") else { return }
            var markerEnd = scan + 1
            if markerEnd < end, isSpaceOrTab(nsText.character(at: markerEnd)) { markerEnd += 1 }
            hiddenDelimiters.append(NSRange(location: scan, length: markerEnd - scan))
            cursor = markerEnd
        }
    }

    private func isSpaceOrTab(_ character: unichar) -> Bool {
        character == Self.utf16(" ") || character == Self.utf16("\t")
    }

    private func isLineTrailing(_ character: unichar) -> Bool {
        isSpaceOrTab(character)
            || character == Self.utf16("\n")
            || character == Self.utf16("\r")
    }

    // MARK: - Inline delimiters

    private mutating func recordDelimiters(of nodeRange: NSRange, minimumWidth: Int) {
        guard let (opening, closing) = delimiterRanges(of: nodeRange, minimumWidth: minimumWidth)
        else { return }
        hiddenDelimiters.append(opening)
        hiddenDelimiters.append(closing)
    }

    /// The run of `*`, `_` or `` ` `` at each end of an inline node.
    ///
    /// swift-markdown reports where a node is but not where its delimiters are,
    /// so they are read back off the source. The run is *measured* rather than
    /// assumed to be two characters for a `Strong` and one for an `Emphasis`,
    /// because an emphasis nested directly inside another is handed the very
    /// same range as its parent: in `***text***` the `Emphasis` and the `Strong`
    /// within it both span all ten characters, and counting a fixed width there
    /// left the innermost asterisk of each run on screen. Only siblings get
    /// inset ranges, as the `Emphasis` inside `**a *b* c**` does.
    ///
    /// Returns nil unless both ends really are a run of the same delimiter, at
    /// least as long as the node needs: whatever this does not positively
    /// recognize stays visible.
    private func delimiterRanges(of nodeRange: NSRange, minimumWidth: Int) -> (NSRange, NSRange)? {
        guard nodeRange.location != NSNotFound,
              nodeRange.length > 2 * minimumWidth,
              NSMaxRange(nodeRange) <= nsText.length else { return nil }

        // Read from the node's own first character: each caller's node type
        // only ever opens with its own kind, so one set covers all three.
        let delimiter = nsText.character(at: nodeRange.location)
        guard delimiter == Self.utf16("*")
                || delimiter == Self.utf16("_")
                || delimiter == Self.utf16("`") else { return nil }

        // Bounded by half the node, so the two runs can never meet and swallow
        // what is between them — and bounded by the node either way, which is
        // what leaves a literal asterisk just outside it alone.
        let limit = nodeRange.length / 2
        var opening = 0
        while opening < limit, nsText.character(at: nodeRange.location + opening) == delimiter {
            opening += 1
        }
        var closing = 0
        while closing < limit, nsText.character(at: NSMaxRange(nodeRange) - 1 - closing) == delimiter {
            closing += 1
        }

        // The shorter of the two: an asymmetric pair means one side is content.
        let width = min(opening, closing)
        guard width >= minimumWidth else { return nil }

        return (
            NSRange(location: nodeRange.location, length: width),
            NSRange(location: NSMaxRange(nodeRange) - width, length: width)
        )
    }

    mutating func visitLink(_ link: Link) {
        if let range = nsRange(for: link) {
            operations.append(.style(kind: .link, range: range, changeFont: false))
            operations.append(.underline(range))
        }
        for child in link.children { visit(child) }
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let full = nsRange(for: listItem) {
            if let markerRange = markerRange(within: full) {
                operations.append(.style(kind: .listMarker, range: markerRange, changeFont: false))
            }
            // Only the line the item starts on. The item's own range covers all
            // of its content — further paragraphs, nested lists — and a
            // paragraph style set across that would space out every paragraph
            // inside it, not the item itself.
            operations.append(.listItemSpacing(firstLineParagraphRange(of: full)))
        }
        for child in listItem.children { visit(child) }
    }

    /// The paragraph containing the start of `itemRange`. Items always begin a
    /// line, so the ranges of two items — nested ones included — never overlap.
    private func firstLineParagraphRange(of itemRange: NSRange) -> NSRange {
        nsText.paragraphRange(for: NSRange(location: itemRange.location, length: 0))
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
