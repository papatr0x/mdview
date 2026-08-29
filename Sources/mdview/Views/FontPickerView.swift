import AppKit
import SwiftUI

/// Lets the user pick both fonts: one for everything that is not code, and a
/// fixed-width one for inline code and fenced blocks.
struct FontPickerView: View {
    @Bindable var preferences = Preferences.shared

    /// Built once per launch rather than per `body` evaluation: each entry
    /// instantiates an `NSFont` to inspect it, and the installed families do
    /// not change while the app is running.
    private static let allFamilies: [String] =
        NSFontManager.shared.availableFontFamilies.sorted()

    /// Code is restricted to fixed-width families — that is what makes code
    /// read as code, and what keeps a fenced block's columns lining up.
    /// The body font carries no such restriction: prose does not need it.
    private static let fixedPitchFamilies: [String] =
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let fontName = members.first?[0] as? String,
                  let font = NSFont(name: fontName, size: 12) else { return false }
            return font.isFixedPitch
        }.sorted()

    var body: some View {
        // A plain Form with explicit labels rather than grouped sections: the
        // Settings window is a fixed 420x460 (see `SettingsView`), and four
        // font rows in a grouped form do not reliably fit inside it.
        Form {
            Picker("Body font", selection: $preferences.bodyFontFamily) {
                ForEach(Self.allFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Stepper(value: $preferences.bodyFontSize, in: Preferences.fontSizeRange, step: 1) {
                Text("Body size: \(Int(preferences.bodyFontSize)) pt")
            }

            Picker("Code font", selection: $preferences.codeFontFamily) {
                ForEach(Self.fixedPitchFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Stepper(value: $preferences.codeFontSize, in: Preferences.fontSizeRange, step: 1) {
                Text("Code size: \(Int(preferences.codeFontSize)) pt")
            }

            Toggle("Bold headings", isOn: $preferences.boldHeadings)
            Toggle("Renumber ordered lists", isOn: $preferences.renumberOrderedLists)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
