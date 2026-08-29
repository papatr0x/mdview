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
    /// everything else, and headings in the bold weight of the body font.
    func font(for kind: MarkdownNodeKind) -> NSFont {
        switch kind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return withTraits(baseFont, bold: boldHeadings, italic: false)
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
