import AppKit

/// The installed font families, split the way the settings need them.
///
/// Built once per launch: inspecting a family means instantiating an `NSFont`
/// for it, and the installed set does not change while the app runs.
enum FontCatalog {
    static let allFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    /// Code is restricted to these — that is what makes code read as code, and
    /// what keeps a fenced block's columns lining up. Body text carries no such
    /// restriction: prose does not need it.
    static let fixedPitchFamilies: [String] = allFamilies.filter { family in
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
              let fontName = members.first?[0] as? String,
              let font = NSFont(name: fontName, size: 12) else { return false }
        return font.isFixedPitch
    }

    static func isFixedPitch(_ family: String) -> Bool {
        fixedPitchFamilies.contains(family)
    }

    /// Ships with every macOS install, and is listed as a family — unlike the
    /// system monospaced font, which `availableFontFamilies` does not expose
    /// and which therefore cannot be offered in a picker.
    static let defaultCodeFamily = "Menlo"
}
