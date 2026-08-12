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
    @State private var isDarkAppearance = ContentView.appearanceIsDark()

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
        .onChange(of: renderInputs) { render() }
    }

    /// Everything the rendered text actually depends on, gathered into one
    /// comparable value.
    ///
    /// One observer instead of one per setting, which matters because the
    /// color wells are continuous: dragging a color used to re-parse and
    /// re-highlight the whole document on the main thread once per mouse
    /// event, in every open window. Two consequences fall out of the shape
    /// of this value:
    ///
    /// - only the *displayed* palette is included, so editing the Light
    ///   colors while viewing Dark (or vice versa) changes nothing on
    ///   screen and now costs nothing;
    /// - a change touching two settings at once renders once, not twice.
    private var renderInputs: RenderInputs {
        RenderInputs(
            palette: preferences.colorTheme.palette(forDark: isDarkAppearance),
            fontFamily: preferences.fontFamily,
            fontSize: preferences.fontSize,
            boldHeadings: preferences.boldHeadings,
            renumberOrderedLists: preferences.renumberOrderedLists
        )
    }

    private struct RenderInputs: Equatable {
        let palette: ColorPalette
        let fontFamily: String
        let fontSize: CGFloat
        let boldHeadings: Bool
        let renumberOrderedLists: Bool
    }

    /// The appearance in effect right now, so the very first render already
    /// uses the right palette.
    ///
    /// Starting at "light" and correcting once the text view reported its
    /// appearance rendered every document twice — the second time in the
    /// colors it should have had — which on a large file shows up as a white
    /// window for as long as the first, wasted, render takes.
    private static func appearanceIsDark() -> Bool {
        // Reading the shared settings first applies any Light/Dark override,
        // so this reflects that override and not only the OS setting.
        _ = Preferences.shared
        return NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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
            style: preferences.style(isDarkAppearance: isDarkAppearance),
            renumberOrderedLists: preferences.renumberOrderedLists
        )
    }
}
