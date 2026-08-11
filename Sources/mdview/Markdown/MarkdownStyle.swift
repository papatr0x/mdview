import AppKit

/// Resolves a `ColorTheme` + font preference into concrete `NSFont`/`NSColor`
/// values for each markdown node kind, for the *currently active* appearance.
///
/// This is a syntax-highlighting style, not a rendering style: every node kind
/// shares the same user-selected font family/size (except code, which is
/// always monospaced) — only color and, for a few node kinds, weight/slant
/// differ, so the document reads like colorized markdown source rather than
/// a re-flowed preview.
struct MarkdownStyle {
    var theme: ColorTheme
    var bodyFontName: String
    var bodyFontSize: CGFloat
    var isDarkAppearance: Bool
    var boldHeadings: Bool

    private var palette: ColorPalette { theme.palette(forDark: isDarkAppearance) }

    var baseFont: NSFont {
        NSFont(name: bodyFontName, size: bodyFontSize) ?? NSFont.systemFont(ofSize: bodyFontSize)
    }

    private var monoFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: bodyFontSize, weight: .regular)
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

    /// The font to use for a node kind: always the user-selected font, except
    /// code (always monospaced) and headings (bold weight of the same font).
    func font(for kind: MarkdownNodeKind) -> NSFont {
        switch kind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return withTraits(baseFont, bold: boldHeadings, italic: false)
        case .inlineCode, .codeBlock:
            return monoFont
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
