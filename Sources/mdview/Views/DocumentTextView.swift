import AppKit
import SwiftUI

/// Reports appearance changes so its own window can re-highlight the text with
/// the matching light/dark palette. Each document window owns one of these, so
/// the callback is per-window rather than a call into shared state.
final class AppearanceAwareTextView: NSTextView, NSLayoutManagerDelegate {
    var onAppearanceChange: ((Bool) -> Void)?

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
        drawFullWidthBackgrounds(in: rect)
    }

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
    private func drawFullWidthBackgrounds(in rect: NSRect) {
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
        guard visibleChars.length > 0,
              NSMaxRange(visibleChars) <= textStorage.length else { return }

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
    let onAppearanceChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AppearanceAwareTextView()
        textView.onAppearanceChange = onAppearanceChange
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
