import AppKit
import SwiftUI

/// Lets the user pick the body font family and size. Code spans/blocks
/// always render monospaced regardless of this choice (see `MarkdownStyle`).
struct FontPickerView: View {
    @Bindable var preferences = Preferences.shared

    private var families: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    var body: some View {
        Form {
            Picker("Font", selection: $preferences.fontFamily) {
                ForEach(families, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Stepper(value: $preferences.fontSize, in: Preferences.fontSizeRange, step: 1) {
                Text("Size: \(Int(preferences.fontSize)) pt")
            }
            Toggle("Bold headings", isOn: $preferences.boldHeadings)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
