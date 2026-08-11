import AppKit
import SwiftUI

/// Preferences panel: one configurable color per markdown node kind, with
/// separate palettes for light and dark appearance.
struct ColorThemePreferencesView: View {
    @Bindable var preferences = Preferences.shared
    @State private var editingDark = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Appearance", selection: $preferences.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            Picker("Editing Palette", selection: $editingDark) {
                Text("Light").tag(false)
                Text("Dark").tag(true)
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(MarkdownNodeKind.allCases) { kind in
                        HStack {
                            Text(kind.displayName)
                            Spacer()
                            ColorWellView(color: colorBinding(for: kind))
                                .frame(width: 44, height: 20)
                        }
                    }
                    HStack {
                        Text("Page background")
                        Spacer()
                        ColorWellView(color: backgroundBinding)
                            .frame(width: 44, height: 20)
                    }
                    HStack {
                        Text("Code block background")
                        Spacer()
                        ColorWellView(color: codeBlockBackgroundBinding)
                            .frame(width: 44, height: 20)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    if editingDark {
                        preferences.colorTheme.dark = .defaultDark
                    } else {
                        preferences.colorTheme.light = .defaultLight
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func colorBinding(for kind: MarkdownNodeKind) -> Binding<NSColor> {
        Binding<NSColor>(
            get: {
                let palette = editingDark ? preferences.colorTheme.dark : preferences.colorTheme.light
                return palette.color(for: kind)
            },
            set: { newValue in
                // Ignore colors with no RGB representation (pattern colors
                // from the system color panel's image palettes).
                guard let rgba = RGBAColor(newValue) else { return }
                if editingDark {
                    preferences.colorTheme.dark.colors[kind] = rgba
                } else {
                    preferences.colorTheme.light.colors[kind] = rgba
                }
            }
        )
    }

    private var backgroundBinding: Binding<NSColor> {
        Binding<NSColor>(
            get: {
                let palette = editingDark ? preferences.colorTheme.dark : preferences.colorTheme.light
                return palette.background.nsColor
            },
            set: { newValue in
                guard let rgba = RGBAColor(newValue) else { return }
                if editingDark {
                    preferences.colorTheme.dark.background = rgba
                } else {
                    preferences.colorTheme.light.background = rgba
                }
            }
        )
    }

    private var codeBlockBackgroundBinding: Binding<NSColor> {
        Binding<NSColor>(
            get: {
                let palette = editingDark ? preferences.colorTheme.dark : preferences.colorTheme.light
                return palette.codeBlockBackground.nsColor
            },
            set: { newValue in
                guard let rgba = RGBAColor(newValue) else { return }
                if editingDark {
                    preferences.colorTheme.dark.codeBlockBackground = rgba
                } else {
                    preferences.colorTheme.light.codeBlockBackground = rgba
                }
            }
        )
    }
}

/// Thin wrapper around the native `NSColorWell` — SwiftUI's `ColorPicker`
/// doesn't expose the same compact native color-well affordance/panel.
private struct ColorWellView: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.color = color
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        if nsView.color != color {
            nsView.color = color
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    final class Coordinator: NSObject {
        let color: Binding<NSColor>
        init(color: Binding<NSColor>) { self.color = color }

        @objc func colorChanged(_ sender: NSColorWell) {
            color.wrappedValue = sender.color
        }
    }
}
