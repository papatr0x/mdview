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

    var fontFamily: String {
        didSet { defaults.set(fontFamily, forKey: Keys.fontFamily) }
    }

    var fontSize: CGFloat {
        didSet { defaults.set(Double(fontSize), forKey: Keys.fontSize) }
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

    var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
            applyAppearance()
        }
    }

    private let defaults: UserDefaults

    static let fontSizeRange: ClosedRange<CGFloat> = 9...36
    private static let fontSizeStep: CGFloat = 1

    private enum Keys {
        static let fontFamily = "mdview.fontFamily"
        static let fontSize = "mdview.fontSize"
        static let colorTheme = "mdview.colorTheme"
        static let boldHeadings = "mdview.boldHeadings"
        static let renumberOrderedLists = "mdview.renumberOrderedLists"
        static let appearanceMode = "mdview.appearanceMode"
    }

    /// - Parameter defaults: the store to read and persist through. Injectable
    ///   so tests can run against a scratch suite: the alternative is writing
    ///   into `UserDefaults.standard`, which is the app's real domain — a test
    ///   would silently overwrite the settings of whoever ran it.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontFamily = defaults.string(forKey: Keys.fontFamily) ?? "Courier New"
        let storedSize = defaults.double(forKey: Keys.fontSize)
        fontSize = storedSize > 0 ? CGFloat(storedSize) : 13
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

    /// Cmd+ and Cmd-.
    func increaseFontSize() {
        fontSize = min(fontSize + Self.fontSizeStep, Self.fontSizeRange.upperBound)
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - Self.fontSizeStep, Self.fontSizeRange.lowerBound)
    }

    /// Resolves these settings against the appearance currently in effect.
    func style(isDarkAppearance: Bool) -> MarkdownStyle {
        MarkdownStyle(
            theme: colorTheme,
            bodyFontName: fontFamily,
            bodyFontSize: fontSize,
            isDarkAppearance: isDarkAppearance,
            boldHeadings: boldHeadings
        )
    }

    private func saveTheme() {
        guard let data = try? JSONEncoder().encode(colorTheme) else { return }
        defaults.set(data, forKey: Keys.colorTheme)
    }
}
