import AppKit

/// The distinct markdown constructs that get their own configurable color.
/// Headings are absent on purpose: they are told apart by size now, not by
/// colour, so there is nothing per-level left to configure. A theme saved by a
/// build that still had them decodes fine — `StoredColors` skips raw values this
/// one does not know rather than discarding the whole map.
enum MarkdownNodeKind: String, CaseIterable, Codable, Identifiable {
    case body
    case blockquote
    case strong
    case emphasis
    case inlineCode
    case codeBlock
    case link
    case listMarker
    case thematicBreak

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .body: return "Body text"
        case .blockquote: return "Blockquote (>)"
        case .strong: return "Bold"
        case .emphasis: return "Italic"
        case .inlineCode: return "Inline code"
        case .codeBlock: return "Code block"
        case .link: return "Link"
        case .listMarker: return "List marker"
        case .thematicBreak: return "Horizontal rule"
        }
    }
}

/// A plain, `Codable`, appearance-independent RGBA color so themes can be
/// persisted to `UserDefaults` without relying on `NSColor`'s archiving.
struct RGBAColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Fails for colors with no RGB representation — notably the pattern
    /// colors selectable from the system color panel's image palettes, whose
    /// `redComponent` raises an exception rather than returning a value.
    init?(_ color: NSColor) {
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        red = Double(converted.redComponent)
        green = Double(converted.greenComponent)
        blue = Double(converted.blueComponent)
        alpha = Double(converted.alphaComponent)
    }
}

/// A single light/dark color palette mapping every node kind to a color, plus
/// the page background and the tint used behind fenced code blocks.
struct ColorPalette: Codable, Equatable {
    var colors: [MarkdownNodeKind: RGBAColor]
    var background: RGBAColor
    var codeBlockBackground: RGBAColor

    private enum CodingKeys: String, CodingKey {
        case colors, background, codeBlockBackground
    }

    init(background: RGBAColor, codeBlockBackground: RGBAColor, colors: [MarkdownNodeKind: RGBAColor]) {
        self.colors = colors
        self.background = background
        self.codeBlockBackground = codeBlockBackground
    }

    init(from decoder: Decoder) throws {
        try self.init(from: decoder, fillingGapsFrom: .defaultLight)
    }

    /// Each background key was introduced after the first release, so a theme
    /// persisted by an older build is missing them. The caller supplies the
    /// defaults for the side being decoded — filling a dark palette from the
    /// light defaults would hand it a white page.
    init(from decoder: Decoder, fillingGapsFrom defaults: ColorPalette) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Node kinds are filled from the defaults the same way the backgrounds
        // are, and for the same reason: a kind added after this theme was saved
        // is simply missing from it. Without the fill it fell through to the
        // *light* defaults — `color(for:)` has no way to know which appearance
        // it belongs to — which in a dark palette meant black text on a black
        // page for every newly added kind.
        let stored = try container.decode(StoredColors.self, forKey: .colors)
        colors = defaults.colors.merging(stored.colors) { _, saved in saved }
        background = try container.decodeIfPresent(RGBAColor.self, forKey: .background)
            ?? defaults.background
        codeBlockBackground = try container.decodeIfPresent(RGBAColor.self, forKey: .codeBlockBackground)
            ?? defaults.codeBlockBackground
    }

    /// A floor, not the gap-filling: a decoded palette already carries every
    /// kind, filled from the defaults for its own appearance. What is left here
    /// is the case of a palette built in code with a kind left out, which
    /// degrades to readable text rather than trapping.
    func color(for kind: MarkdownNodeKind) -> NSColor {
        (colors[kind] ?? ColorPalette.defaultLight.colors[kind])?.nsColor ?? .labelColor
    }

    static let defaultLight = ColorPalette(
        background: RGBAColor(red: 1.0, green: 1.0, blue: 1.0),
        codeBlockBackground: RGBAColor(red: 0.88, green: 0.93, blue: 1.0),
        colors: [
        .body: RGBAColor(red: 0.0, green: 0.0, blue: 0.0),
        .blockquote: RGBAColor(red: 0.35, green: 0.35, blue: 0.4),
        .strong: RGBAColor(red: 0.0, green: 0.0, blue: 0.0),
        .emphasis: RGBAColor(red: 0.0, green: 0.0, blue: 0.0),
        .inlineCode: RGBAColor(red: 0.60, green: 0.09, blue: 0.44),
        .codeBlock: RGBAColor(red: 0.15, green: 0.15, blue: 0.15),
        .link: RGBAColor(red: 0.0, green: 0.35, blue: 0.85),
        .listMarker: RGBAColor(red: 0.30, green: 0.30, blue: 0.30),
        .thematicBreak: RGBAColor(red: 0.6, green: 0.6, blue: 0.6)
    ])

    static let defaultDark = ColorPalette(
        background: RGBAColor(red: 0.12, green: 0.12, blue: 0.13),
        codeBlockBackground: RGBAColor(red: 0.08, green: 0.14, blue: 0.26),
        colors: [
        .body: RGBAColor(red: 0.92, green: 0.92, blue: 0.92),
        .blockquote: RGBAColor(red: 0.65, green: 0.65, blue: 0.75),
        .strong: RGBAColor(red: 1.0, green: 1.0, blue: 1.0),
        .emphasis: RGBAColor(red: 0.92, green: 0.92, blue: 0.92),
        .inlineCode: RGBAColor(red: 0.95, green: 0.55, blue: 0.85),
        .codeBlock: RGBAColor(red: 0.85, green: 0.85, blue: 0.85),
        .link: RGBAColor(red: 0.40, green: 0.65, blue: 1.0),
        .listMarker: RGBAColor(red: 0.75, green: 0.75, blue: 0.75),
        .thematicBreak: RGBAColor(red: 0.5, green: 0.5, blue: 0.5)
    ])
}

/// The `colors` map as `JSONEncoder` writes it for a dictionary keyed by an
/// enum: a flat array of alternating raw key and value.
///
/// Decoded by hand only to be forgiving about the keys. The synthesized
/// dictionary decoder rejects the *entire* map on meeting one raw value it does
/// not recognize, and `Preferences` reads the theme with `try?` — so a single
/// unknown kind, which is what a theme written by a newer build looks like,
/// silently discarded every color the user had chosen, in both palettes.
private struct StoredColors: Decodable {
    let colors: [MarkdownNodeKind: RGBAColor]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [MarkdownNodeKind: RGBAColor] = [:]
        while !container.isAtEnd {
            let rawKind = try container.decode(String.self)
            // Decoded whether or not the kind is known: the value has to be
            // consumed either way to stay aligned with the next key.
            let color = try container.decode(RGBAColor.self)
            if let kind = MarkdownNodeKind(rawValue: rawKind) {
                decoded[kind] = color
            }
        }
        colors = decoded
    }
}

/// A user-configurable color theme: one palette for light appearance, one for dark.
struct ColorTheme: Codable, Equatable {
    var light: ColorPalette
    var dark: ColorPalette

    static let `default` = ColorTheme(light: .defaultLight, dark: .defaultDark)

    private enum CodingKeys: String, CodingKey {
        case light, dark
    }

    init(light: ColorPalette, dark: ColorPalette) {
        self.light = light
        self.dark = dark
    }

    /// Decodes each side against its own defaults, so keys added after a theme
    /// was persisted are filled in with the right values for that appearance.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        light = try ColorPalette(
            from: container.superDecoder(forKey: .light),
            fillingGapsFrom: .defaultLight
        )
        dark = try ColorPalette(
            from: container.superDecoder(forKey: .dark),
            fillingGapsFrom: .defaultDark
        )
    }

    func palette(forDark isDark: Bool) -> ColorPalette {
        isDark ? dark : light
    }
}
