import AppKit
import SwiftUI

/// Reports appearance changes so its own window can re-highlight the text with
/// the matching light/dark palette. Each document window owns one of these, so
/// the callback is per-window rather than a call into shared state.
final class AppearanceAwareTextView: NSTextView {
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
            layoutManager.enumerateLineFragments(forGlyphRange: runGlyphs) { lineRect, _, _, _, _ in
                NSBezierPath(rect: lineRect.offsetBy(dx: origin.x, dy: origin.y)).fill()
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
