import AppKit
import SwiftUI

/// Lets the user pick both fonts: one for everything that is not code, and a
/// fixed-width one for inline code and fenced blocks.
struct FontPickerView: View {
    @Bindable var preferences = Preferences.shared

    /// Whatever is configured is always offered, even if it is not a
    /// fixed-width family — a Picker with no matching tag renders blank, which
    /// hides the real setting instead of showing it.
    private var codeFamilies: [String] {
        let families = FontCatalog.fixedPitchFamilies
        return families.contains(preferences.codeFontFamily)
            ? families
            : (families + [preferences.codeFontFamily]).sorted()
    }

    var body: some View {
        // A plain Form with explicit labels rather than grouped sections: the
        // Settings window is a fixed 420x460 (see `SettingsView`), and four
        // font rows in a grouped form do not reliably fit inside it.
        Form {
            Picker("Body font", selection: $preferences.bodyFontFamily) {
                ForEach(FontCatalog.allFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Stepper(value: $preferences.bodyFontSize, in: Preferences.fontSizeRange, step: 1) {
                Text("Body size: \(Int(preferences.bodyFontSize)) pt")
            }

            Picker("Code font", selection: $preferences.codeFontFamily) {
                ForEach(codeFamilies, id: \.self) { family in
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
