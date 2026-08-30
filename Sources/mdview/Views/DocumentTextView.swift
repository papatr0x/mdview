import AppKit
import SwiftUI

/// Reports appearance changes so its own window can re-highlight the text with
/// the matching light/dark palette. Each document window owns one of these, so
/// the callback is per-window rather than a call into shared state.
final class AppearanceAwareTextView: NSTextView, NSLayoutManagerDelegate {
    var onAppearanceChange: ((Bool) -> Void)?

    /// The rules down the left of a blockquote. Passed in rather than read off
    /// the text, so it comes from the same resolved style as everything else.
    var blockquoteBarColor: NSColor = .secondaryLabelColor

    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Deferred by one turn on purpose: this callback runs inside AppKit's
        // appearance update, and re-rendering synchronously would replace this
        // very view's text storage from within its own callback.
        let isDark = isDarkAppearance
        Task { @MainActor [weak self] in
            self?.onAppearanceChange?(isDark)
        }
    }

    /// Drops the glyphs for characters the renderer marked as emphasis
    /// delimiters, so `**bold**` reads as bold rather than as bold asterisks
    /// wrapped around bold text.
    ///
    /// Done here rather than by deleting the characters, which is the whole
    /// point: a `.null` glyph is not drawn and takes no width, while the
    /// character stays in the text storage. The document on screen is still the
    /// file — selecting a bold phrase and copying it gives back the `**`, and
    /// every range the renderer recorded still lines up with the source.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let textStorage, glyphRange.length > 0 else { return 0 }

        var adjusted: [NSLayoutManager.GlyphProperty] = []
        var hidAny = false
        for offset in 0..<glyphRange.length {
            let characterIndex = characterIndexes[offset]
            let isDelimiter = characterIndex < textStorage.length
                && textStorage.attribute(
                    .hiddenMarkdownDelimiter,
                    at: characterIndex,
                    effectiveRange: nil
                ) != nil
            if isDelimiter { hidAny = true }
            adjusted.append(isDelimiter ? .null : properties[offset])
        }
        // Returning 0 leaves the layout manager's own glyphs in place, which is
        // both cheaper and safer than handing back a copy of what it gave us.
        guard hidAny else { return 0 }

        layoutManager.setGlyphs(
            glyphs,
            properties: adjusted,
            characterIndexes: characterIndexes,
            font: font,
            forGlyphRange: glyphRange
        )
        return glyphRange.length
    }

    /// Full width from the line fragment, height from the used rect.
    ///
    /// The fragment is the taller of the two whenever the line carries
    /// paragraph spacing — the space a list item reserves above itself lives
    /// inside its first line's fragment. Filling the fragment therefore painted
    /// that gap as well, which shows as a band of code-block background hanging
    /// above a fenced block that opens a list item (`- ` and the opening fence
    /// on one line). Without spacing the two rects are identical, so this
    /// changes nothing anywhere else.
    static func fullWidthFillRect(fragment: NSRect, used: NSRect) -> NSRect {
        NSRect(x: fragment.minX, y: used.minY, width: fragment.width, height: used.height)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        withVisibleText(in: rect) { layoutManager, textStorage, visibleChars, origin in
            drawFullWidthBackgrounds(layoutManager, textStorage, visibleChars, origin)
            drawBlockquoteBars(layoutManager, textStorage, visibleChars, origin)
        }
    }

    /// The visible slice of the document, resolved once for the two things that
    /// paint underneath the text.
    ///
    /// Only the on-screen portion is inspected: walking the whole text storage
    /// here would force layout of the entire document on every redraw, which is
    /// exactly the lazy-layout behaviour `NSTextView` is being used for in the
    /// first place.
    private func withVisibleText(
        in rect: NSRect,
        _ body: (NSLayoutManager, NSTextStorage, NSRange, NSPoint) -> Void
    ) {
        guard let layoutManager, let textContainer, let textStorage else { return }

        // AppKit passes this method the text view's full bounds — which, for a
        // long document inside a scroll view, is the height of the entire file
        // rather than the scrolled-to page. Clamping to `visibleRect` keeps the
        // work proportional to what is on screen instead of to the file size.
        let exposed = rect.intersection(visibleRect)
        let target = exposed.isEmpty ? rect : exposed

        let origin = textContainerOrigin
        let containerRect = target.offsetBy(dx: -origin.x, dy: -origin.y)
        // Deliberately the "withoutAdditionalLayout" variant: this runs inside
        // the draw pass, and forcing new layout here re-enters the layout
        // manager mid-draw, which can leave glyphs unpainted. Anything not yet
        // laid out simply gets skipped and painted on a later pass.
        let visibleGlyphs = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: containerRect,
            in: textContainer
        )
        guard visibleGlyphs.length > 0 else { return }

        let visibleChars = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        guard visibleChars.length > 0, NSMaxRange(visibleChars) <= textStorage.length else { return }

        body(layoutManager, textStorage, visibleChars, origin)
    }

    /// One rule per level of nesting, stepped by the same indent the paragraph
    /// style uses, so each bar sits at the edge of the text it encloses.
    ///
    /// Walks the quote's own lines rather than enumerating the run's line
    /// fragments, because those do not line up with them. A quote's run starts
    /// on the hidden `>`, and TextKit packs a null glyph onto the end of the
    /// *previous* line's fragment — it has no width, so it fits there. The
    /// first fragment handed back therefore belongs to the line above: painting
    /// it drew every bar one line high, and left one standing on the blank line
    /// between two quotes.
    private func drawBlockquoteBars(
        _ layoutManager: NSLayoutManager,
        _ textStorage: NSTextStorage,
        _ visibleChars: NSRange,
        _ origin: NSPoint
    ) {
        let text = textStorage.string as NSString
        blockquoteBarColor.setFill()
        textStorage.enumerateAttribute(.blockquoteLevel, in: visibleChars, options: []) { value, range, _ in
            guard let level = value as? Int, level > 0, range.length > 0 else { return }

            var lineStart = range.location
            while lineStart < NSMaxRange(range) {
                let line = text.paragraphRange(for: NSRange(location: lineStart, length: 0))
                guard line.length > 0 else { return }
                lineStart = NSMaxRange(line)

                guard let glyph = self.drawnGlyph(on: line, in: text, layoutManager) else { continue }
                let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
                for depth in 0..<level {
                    let bar = NSRect(
                        x: fragment.minX + CGFloat(depth) * MarkdownStyle.blockquoteIndent + Self.barInset,
                        y: used.minY,
                        width: Self.barWidth,
                        height: used.height
                    )
                    NSBezierPath(rect: bar.offsetBy(dx: origin.x, dy: origin.y)).fill()
                }
            }
        }
    }

    /// A glyph on this line that is actually drawn, searched from the right so
    /// the hidden markers at the start are stepped over. Nil for a line with
    /// nothing on it but markers, which has no text to put a bar beside.
    func drawnGlyph(
        on line: NSRange,
        in text: NSString,
        _ layoutManager: NSLayoutManager
    ) -> Int? {
        var index = NSMaxRange(line) - 1
        while index >= line.location {
            let character = text.character(at: index)
            if character != 0x0A, character != 0x0D {
                let glyph = layoutManager.glyphIndexForCharacter(at: index)
                if layoutManager.propertyForGlyph(at: glyph) != .null { return glyph }
            }
            index -= 1
        }
        return nil
    }

    private static let barWidth: CGFloat = 3
    private static let barInset: CGFloat = 4

    /// `NSAttributedString.backgroundColor` only fills each line's actual
    /// glyph width, so a short line (a fenced code block's opening/closing
    /// "```") ends up narrower than the block's content lines, producing a
    /// jagged edge instead of a solid rectangle. Filling each line's full
    /// fragment rect ourselves, underneath the normal text drawing, gives
    /// fenced code blocks a uniform, full-width "block" background.
    ///
    /// Only the on-screen portion is inspected: walking the whole text storage
    /// here would force layout of the entire document on every redraw, which
    /// is exactly the lazy-layout behaviour `NSTextView` is being used for in
    /// the first place.
    private func drawFullWidthBackgrounds(
        _ layoutManager: NSLayoutManager,
        _ textStorage: NSTextStorage,
        _ visibleChars: NSRange,
        _ origin: NSPoint
    ) {
        textStorage.enumerateAttribute(.backgroundColor, in: visibleChars, options: []) { value, range, _ in
            guard let color = value as? NSColor, range.length > 0 else { return }
            let runGlyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            color.setFill()
            layoutManager.enumerateLineFragments(forGlyphRange: runGlyphs) { lineRect, usedRect, _, _, _ in
                let fill = Self.fullWidthFillRect(fragment: lineRect, used: usedRect)
                NSBezierPath(rect: fill.offsetBy(dx: origin.x, dy: origin.y)).fill()
            }
        }
    }
}

/// Read-only, scrollable text surface. Backed by `NSTextView` rather than a
/// SwiftUI `Text`/`ScrollView` because `NSTextView` lays out and draws only
/// the visible portion of the (potentially large) document, which is the
/// more resource-efficient option for a viewer.
struct DocumentTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    let backgroundColor: NSColor
    let blockquoteBarColor: NSColor
    let onAppearanceChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AppearanceAwareTextView()
        textView.onAppearanceChange = onAppearanceChange
        textView.blockquoteBarColor = blockquoteBarColor
        // Weak on NSLayoutManager, so the view owning its own layout manager's
        // delegate is not a retain cycle.
        textView.layoutManager?.delegate = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        // The scroll view shows through wherever the document is shorter than
        // the window, so it has to carry the same color as the text view.
        applyBackgroundColor(to: textView, scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AppearanceAwareTextView else { return }
        textView.onAppearanceChange = onAppearanceChange
        if textView.blockquoteBarColor != blockquoteBarColor {
            textView.blockquoteBarColor = blockquoteBarColor
            textView.needsDisplay = true
        }
        applyBackgroundColor(to: textView, scrollView)
        guard textView.textStorage?.isEqual(to: attributedText) == false else { return }
        textView.textStorage?.setAttributedString(attributedText)
    }

    private func applyBackgroundColor(to textView: NSTextView, _ scrollView: NSScrollView) {
        guard textView.backgroundColor != backgroundColor else { return }
        textView.backgroundColor = backgroundColor
        scrollView.backgroundColor = backgroundColor
    }
}
