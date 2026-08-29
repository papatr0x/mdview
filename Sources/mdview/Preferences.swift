import AppKit
import Observation

/// Overrides the window/app appearance, independent of which color palette
/// (light/dark) a rendered document then picks up.
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Display settings shared by every open document window: changing the font or
/// a highlight color re-styles all of them at once. Document contents live in
/// `MarkdownDocument`, one per window.
///
/// Deliberately not `@MainActor`-annotated: under the Swift 5.10 toolchain this
/// package supports, SwiftUI's escaping `Binding` and `Button` closures do not
/// inherit actor isolation, which would make every view-layer call site an
/// error. All mutation happens on the main thread regardless.
@Observable
final class Preferences {
    static let shared = Preferences()

    /// Everything that is not code.
    var bodyFontFamily: String {
        didSet { defaults.set(bodyFontFamily, forKey: Keys.bodyFontFamily) }
    }

    var bodyFontSize: CGFloat {
        didSet { defaults.set(Double(bodyFontSize), forKey: Keys.bodyFontSize) }
    }

    /// Inline code and fenced blocks. The settings only offer fixed-width
    /// families here, which is what keeps code reading as code.
    var codeFontFamily: String {
        didSet { defaults.set(codeFontFamily, forKey: Keys.codeFontFamily) }
    }

    var codeFontSize: CGFloat {
        didSet { defaults.set(Double(codeFontSize), forKey: Keys.codeFontSize) }
    }

    var colorTheme: ColorTheme {
        didSet { saveTheme() }
    }

    var boldHeadings: Bool {
        didSet { defaults.set(boldHeadings, forKey: Keys.boldHeadings) }
    }

    /// Shows ordered-list items with their real position instead of the
    /// numeral written in the file. Off means a strictly verbatim view.
    var renumberOrderedLists: Bool {
        didSet { defaults.set(renumberOrderedLists, forKey: Keys.renumberOrderedLists) }
    }

    /// Points of vertical space before each list item, ordered or not. Zero
    /// switches it off.
    var listItemSpacing: CGFloat {
        didSet { defaults.set(Double(listItemSpacing), forKey: Keys.listItemSpacing) }
    }

    var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
            applyAppearance()
        }
    }

    private let defaults: UserDefaults

    static let fontSizeRange: ClosedRange<CGFloat> = 9...36
    static let listItemSpacingRange: ClosedRange<CGFloat> = 0...20
    private static let fontSizeStep: CGFloat = 1

    private enum Keys {
        // The body keys predate the split, and keep their original names so
        // that the family a user already chose stays their body font.
        static let bodyFontFamily = "mdview.fontFamily"
        static let bodyFontSize = "mdview.fontSize"
        static let codeFontFamily = "mdview.codeFontFamily"
        static let codeFontSize = "mdview.codeFontSize"
        static let colorTheme = "mdview.colorTheme"
        static let boldHeadings = "mdview.boldHeadings"
        static let renumberOrderedLists = "mdview.renumberOrderedLists"
        static let listItemSpacing = "mdview.listItemSpacing"
        static let appearanceMode = "mdview.appearanceMode"
    }

    /// - Parameter defaults: the store to read and persist through. Injectable
    ///   so tests can run against a scratch suite: the alternative is writing
    ///   into `UserDefaults.standard`, which is the app's real domain — a test
    ///   would silently overwrite the settings of whoever ran it.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedBodyFamily = defaults.string(forKey: Keys.bodyFontFamily)
        bodyFontFamily = storedBodyFamily ?? "Courier New"
        let storedBodySize = defaults.double(forKey: Keys.bodyFontSize)
        let resolvedBodySize: CGFloat = storedBodySize > 0 ? CGFloat(storedBodySize) : 13
        bodyFontSize = resolvedBodySize

        // Upgrading from a build that had one font: that family seeds the code
        // font too, rather than surprising anyone with one they never chose —
        // but only if it is actually fixed-width. It is not necessarily: the
        // old picker offered nothing else, yet the body font is unrestricted
        // now, so by the time this runs the stored family may well be
        // proportional.
        let storedCodeFamily = defaults.string(forKey: Keys.codeFontFamily)
        codeFontFamily = storedCodeFamily
            ?? storedBodyFamily.flatMap { FontCatalog.isFixedPitch($0) ? $0 : nil }
            ?? FontCatalog.defaultCodeFamily
        let storedCodeSize = defaults.double(forKey: Keys.codeFontSize)
        codeFontSize = storedCodeSize > 0 ? CGFloat(storedCodeSize) : resolvedBodySize
        // Zero is a meaningful value here — it means "no spacing" — so absence
        // has to be told apart from it, which `double(forKey:)` alone cannot do.
        listItemSpacing = defaults.object(forKey: Keys.listItemSpacing) == nil
            ? 4
            : CGFloat(defaults.double(forKey: Keys.listItemSpacing))
        boldHeadings = defaults.object(forKey: Keys.boldHeadings) as? Bool ?? true
        renumberOrderedLists = defaults.object(forKey: Keys.renumberOrderedLists) as? Bool ?? true
        appearanceMode = defaults.string(forKey: Keys.appearanceMode)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system

        if let data = defaults.data(forKey: Keys.colorTheme),
           let decoded = try? JSONDecoder().decode(ColorTheme.self, from: data) {
            colorTheme = decoded
        } else {
            colorTheme = .default
        }

        // Written once, on the launch that first needs it. Every other default
        // is a constant and can be re-derived at each launch, but this one is
        // derived from another setting: leaving it unwritten made the code font
        // silently follow the body font every time the body font changed.
        if storedCodeFamily == nil {
            defaults.set(codeFontFamily, forKey: Keys.codeFontFamily)
        }
    }

    /// Pushes the stored Light/Dark override onto the running app.
    ///
    /// Deliberately not done from `init`: an initializer that reconfigures
    /// global UI state is hard to reason about wherever it runs, and it made
    /// the type impossible to construct at all outside a running app — `NSApp`
    /// is nil in a test bundle, so the assignment trapped. The app calls this
    /// once at launch; changing `appearanceMode` calls it again.
    func applyAppearance() {
        NSApp?.appearance = appearanceMode.nsAppearance
    }

    /// Cmd+ and Cmd-. Both fonts move together — zooming a document means
    /// zooming all of it — each clamped to the range on its own.
    func increaseFontSize() {
        bodyFontSize = min(bodyFontSize + Self.fontSizeStep, Self.fontSizeRange.upperBound)
        codeFontSize = min(codeFontSize + Self.fontSizeStep, Self.fontSizeRange.upperBound)
    }

    func decreaseFontSize() {
        bodyFontSize = max(bodyFontSize - Self.fontSizeStep, Self.fontSizeRange.lowerBound)
        codeFontSize = max(codeFontSize - Self.fontSizeStep, Self.fontSizeRange.lowerBound)
    }

    /// Resolves these settings against the appearance currently in effect.
    func style(isDarkAppearance: Bool) -> MarkdownStyle {
        MarkdownStyle(
            theme: colorTheme,
            bodyFontName: bodyFontFamily,
            bodyFontSize: bodyFontSize,
            codeFontName: codeFontFamily,
            codeFontSize: codeFontSize,
            isDarkAppearance: isDarkAppearance,
            boldHeadings: boldHeadings,
            listItemSpacing: listItemSpacing
        )
    }

    private func saveTheme() {
        guard let data = try? JSONEncoder().encode(colorTheme) else { return }
        defaults.set(data, forKey: Keys.colorTheme)
    }
}
