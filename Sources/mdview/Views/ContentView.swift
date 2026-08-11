import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One document window. The rendered text is derived state: it is rebuilt
/// whenever the document, the shared display settings, or the effective
/// light/dark appearance changes.
struct ContentView: View {
    let document: MarkdownDocument

    @Bindable private var preferences = Preferences.shared
    @State private var attributedText = NSAttributedString(string: "")
    @State private var isDarkAppearance = false

    var body: some View {
        DocumentTextView(
            attributedText: attributedText,
            backgroundColor: preferences.style(isDarkAppearance: isDarkAppearance).backgroundColor,
            onAppearanceChange: { isDark in
                // Drives a re-render only when the appearance actually flips.
                if isDarkAppearance != isDark { isDarkAppearance = isDark }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .onAppear { render() }
        .onChange(of: document.text) { render() }
        .onChange(of: isDarkAppearance) { render() }
        .onChange(of: preferences.fontFamily) { render() }
        .onChange(of: preferences.fontSize) { render() }
        .onChange(of: preferences.boldHeadings) { render() }
        .onChange(of: preferences.colorTheme) { render() }
    }

    /// A dropped file opens in its own window, the same as a double-click,
    /// rather than replacing what this window is showing.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            // The provider calls back on an arbitrary queue.
            Task { @MainActor in
                NSDocumentController.shared.openDocument(
                    withContentsOf: url,
                    display: true
                ) { _, _, _ in }
            }
        }
        return true
    }

    private func render() {
        attributedText = MarkdownRenderer.render(
            markdown: document.text,
            style: preferences.style(isDarkAppearance: isDarkAppearance)
        )
    }
}
