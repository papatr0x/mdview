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
    /// Survives across renders, so only the first one pays for parsing.
    @State private var plans = StylePlanCache()
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
        .background(fontSizeShortcutAlias)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .onAppear { render() }
        .onChange(of: document.text) { render() }
        .onChange(of: renderInputs) { render() }
    }

    /// Cmd+= as an alias for the menu's Cmd++.
    ///
    /// On US/UK layouts "+" is a shifted key, so the menu shortcut alone
    /// makes zooming in a three-finger chord; every macOS app accepts "="
    /// as the unshifted equivalent. SwiftUI allows one shortcut per menu
    /// command, so the alias lives here as a zero-sized button rather than
    /// as a duplicate menu entry.
    private var fontSizeShortcutAlias: some View {
        Button("") { preferences.increaseFontSize() }
            .keyboardShortcut("=", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
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
            bodyFontFamily: preferences.bodyFontFamily,
            bodyFontSize: preferences.bodyFontSize,
            codeFontFamily: preferences.codeFontFamily,
            codeFontSize: preferences.codeFontSize,
            boldHeadings: preferences.boldHeadings,
            renumberOrderedLists: preferences.renumberOrderedLists,
            listItemSpacing: preferences.listItemSpacing
        )
    }

    private struct RenderInputs: Equatable {
        let palette: ColorPalette
        let bodyFontFamily: String
        let bodyFontSize: CGFloat
        let codeFontFamily: String
        let codeFontSize: CGFloat
        let boldHeadings: Bool
        let renumberOrderedLists: Bool
        let listItemSpacing: CGFloat
    }

    /// The appearance in effect right now, so the very first render already
    /// uses the right palette.
    ///
    /// Starting at "light" and correcting once the text view reported its
    /// appearance rendered every document twice — the second time in the
    /// colors it should have had — which on a large file shows up as a white
    /// window for as long as the first, wasted, render takes.
    private static func appearanceIsDark() -> Bool {
        // `MdviewApp.init` has already pushed any Light/Dark override onto the
        // app, so this reflects that override and not only the OS setting.
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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

    /// Repaints from the plan already in hand, or — the first time this
    /// document is shown — lets the window come up and paints once the parse
    /// finishes.
    ///
    /// Parsing is the expensive half, and doing it inline was what held up the
    /// first frame at launch: macOS restores every window that was open when
    /// the app last quit, each one parsed in turn on the main thread, and
    /// nothing at all was drawn until the last of them finished. So a small
    /// document waited on a large one it had nothing to do with. Off the main
    /// thread they parse alongside each other and each window appears at once.
    private func render() {
        let text = document.text
        if let plan = plans.cachedPlan(for: text) {
            paint(plan, of: text)
            return
        }
        // Explicitly on the main actor: painting resolves NSFont/NSColor and
        // writes view state, neither of which may happen on the parse's thread.
        Task { @MainActor in
            let plan = await plans.plan(for: text)
            paint(plan, of: text)
        }
    }

    /// Settings can move while a parse runs, so the style is read here rather
    /// than captured when the parse started.
    private func paint(_ plan: StylePlan, of text: String) {
        attributedText = MarkdownRenderer.render(
            plan: plan,
            markdown: text,
            style: preferences.style(isDarkAppearance: isDarkAppearance),
            renumberOrderedLists: preferences.renumberOrderedLists
        )
    }
}
