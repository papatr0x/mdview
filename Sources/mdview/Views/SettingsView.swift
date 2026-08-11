import SwiftUI

/// Backs the standard macOS "mdview > Settings…" menu item (Cmd+,).
struct SettingsView: View {
    var body: some View {
        TabView {
            FontPickerView()
                .tabItem { Label("Font", systemImage: "textformat") }

            ColorThemePreferencesView()
                .tabItem { Label("Colors", systemImage: "paintpalette") }
        }
        // A fixed (not min/max) size keeps the Settings window from
        // resizing when switching tabs — the two tabs' content sizes
        // otherwise differ enough to make the window visibly jump/shrink.
        .frame(width: 420, height: 460)
    }
}
