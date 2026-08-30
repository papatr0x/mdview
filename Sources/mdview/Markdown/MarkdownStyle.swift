import AppKit

/// Resolves a `ColorTheme` + font preferences into concrete `NSFont`/`NSColor`
/// values for each markdown node kind, for the *currently active* appearance.
///
/// This is a syntax-highlighting style, not a rendering style: nothing is
/// re-flowed, only colored, and — for a few node kinds — given weight or slant.
///
/// Two fonts, both the user's: everything that is not code uses the body font,
/// and inline code and fenced blocks use the code font, which the settings
/// restrict to a fixed-width family. They carry independent sizes because the
/// same point size rarely looks the same across two families.
struct MarkdownStyle {
    var theme: ColorTheme
    var bodyFontName: String
    var bodyFontSize: CGFloat
    var codeFontName: String
    var codeFontSize: CGFloat
    var isDarkAppearance: Bool
    var boldHeadings: Bool
    /// Points of vertical space before each list item. Zero means none, and
    /// then no paragraph style is applied at all.
    var listItemSpacing: CGFloat

    private var palette: ColorPalette { theme.palette(forDark: isDarkAppearance) }

    var baseFont: NSFont {
        NSFont(name: bodyFontName, size: bodyFontSize) ?? NSFont.systemFont(ofSize: bodyFontSize)
    }

    /// Falls back to the system monospaced font, which is what code always used
    /// before the family became configurable — so an unavailable or uninstalled
    /// choice still renders code as code.
    private var codeFont: NSFont {
        NSFont(name: codeFontName, size: codeFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
    }

    /// A heading's font: the body family, resized by level, in whatever weight
    /// the "Bold headings" setting asks for.
    ///
    /// Since headings carry no colour of their own any more, size is the only
    /// thing telling one level from another — and telling any of them from body
    /// text, given the `#` is not drawn either. So the scale is strictly
    /// decreasing and **no level lands on the body size**: H6 sits just under
    /// it rather than on it.
    func headingFont(level: Int) -> NSFont {
        let clamped = min(max(level, 1), Self.headingScale.count)
        let size = (bodyFontSize * Self.headingScale[clamped - 1]).rounded()
        let font = NSFont(name: bodyFontName, size: size) ?? NSFont.systemFont(ofSize: size)
        return withTraits(font, bold: boldHeadings, italic: false)
    }

    /// Held to 1.6 rather than the 2.0 a browser would use: this is still a
    /// source viewer, and a heading has to sit in the same column of text as
    /// everything around it.
    private static let headingScale: [CGFloat] = [1.60, 1.42, 1.28, 1.15, 1.05, 0.95]

    /// How far a blockquote is pushed in per level of nesting, and the step
    /// between the bars drawn down its left edge.
    static let blockquoteIndent: CGFloat = 18

    func color(for kind: MarkdownNodeKind) -> NSColor {
        palette.color(for: kind)
    }

    /// The page color behind the whole document.
    var backgroundColor: NSColor {
        palette.background.nsColor
    }

    var codeBlockBackgroundColor: NSColor {
        palette.codeBlockBackground.nsColor
    }

    /// The font for a node kind: the code font for code, the body font for
    /// everything else. Headings go through `headingFont(level:)` instead,
    /// since what distinguishes them is a size.
    func font(for kind: MarkdownNodeKind) -> NSFont {
        switch kind {
        case .inlineCode, .codeBlock:
            return codeFont
        default:
            return baseFont
        }
    }

    /// Applies bold/italic traits on top of whatever font is passed in
    /// (typically the font already resolved for the enclosing node kind).
    func withTraits(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        guard !traits.isEmpty else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: traits)
    }
}
