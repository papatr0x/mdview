import AppKit
import SwiftUI

/// Lets the user pick the body font family and size. Code spans/blocks
/// always render monospaced regardless of this choice (see `MarkdownStyle`).
struct FontPickerView: View {
    @Bindable var preferences = Preferences.shared

    /// Only fixed-width (monospaced) families are offered — mdview is meant
    /// to read like colorized source text, which relies on consistent
    /// character width (list/quote indentation, alignment of `#`/`>`
    /// markers, etc.).
    private var families: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let fontName = members.first?[0] as? String,
                  let font = NSFont(name: fontName, size: 12) else { return false }
            return font.isFixedPitch
        }.sorted()
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
            Toggle("Renumber ordered lists", isOn: $preferences.renumberOrderedLists)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
