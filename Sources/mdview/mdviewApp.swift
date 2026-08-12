import SwiftUI

@main
struct MdviewApp: App {
    var body: some Scene {
        // A viewing-only `DocumentGroup`: macOS opens each file in its own
        // window, and routes double-click, "Open With", `open`, and the Open
        // panel through it — no app-delegate handling needed. Display settings
        // stay shared across those windows via `Preferences`.
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document)
        }
        .commands {
            // In the View menu, where macOS puts zoom — not Edit, which is
            // for changing the document (and this app never does).
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    Preferences.shared.increaseFontSize()
                }
                // "+" is what the menu should read, and it is an unshifted
                // key on ISO layouts. Where it is *not* — US/UK, where it
                // costs a Shift — the conventional "=" alias is bound in
                // `ContentView`, since SwiftUI allows only one shortcut here.
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    Preferences.shared.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)
            }
        }

        // Backs the standard "mdview > Settings…" menu item (Cmd+,), the
        // idiomatic macOS home for font/color preferences.
        Settings {
            SettingsView()
        }
    }
}
