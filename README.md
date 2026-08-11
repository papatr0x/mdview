# mdview

A lightweight, native macOS Markdown **viewer**. mdview shows Markdown files as syntax-highlighted source — headers, quotes, bold/italic, code, links, and lists are colorized in place — rather than rendering them into HTML-style formatted output. It's read-only, scrollable, and fully configurable.

## Features

- **Syntax highlighting, not rendering** — the raw Markdown text (`#`, `>`, `**`, backticks, …) stays visible, colorized by node type, like a source-code editor rather than a browser preview.
- **Configurable colors** — every node type (headings, blockquote, bold, italic, inline code, code blocks, links, list markers) has its own color, with separate palettes for light and dark appearance.
- **Fenced code blocks** render with a full-width background block and always use a monospaced font, regardless of the body font.
- **Appearance control** — follow the system, or force Light / Dark, independent of the rest of macOS.
- **Font picker** — any installed font family and size; defaults to Courier New.
- **Optional bold headings** toggle.
- **Read-only and scrollable** — `NSTextView`-backed for efficient rendering of large documents; text is selectable/copyable but not editable.
- **One window per file** — each document gets its own window, scroll position, and title. Opening a file that is already open brings its window forward instead of duplicating it, and display settings are shared across every open window.
- **Opens files three ways**: File > Open… (Cmd+O, with Open Recent), drag & drop onto a window, or double-click / "Open With" in Finder once registered as a `.md`/`.markdown` handler.
- Cmd+ / Cmd- to change the font size on the fly.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.10+ toolchain to build from source

## Clone

```sh
git clone https://github.com/papatr0x/mdview.git
cd mdview
```

## Build

mdview is a Swift Package Manager project (no `.xcodeproj`). It depends on Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) for parsing, resolved automatically on first build.

```sh
swift build -c release
swift test
```

### Producing a `.app` bundle

A plain `swift build` produces a raw executable, not a double-clickable app (needed for Finder integration, Dock icon, and document-type registration). Use the provided script:

```sh
./Scripts/build-app.sh
```

This builds in release mode, assembles `dist/mdview.app` (icon, `Info.plist`), and code-signs it with **App Sandbox** enabled (`Sources/mdview/Resources/mdview.entitlements`: sandbox on, read-only access to user-selected/dropped files — sufficient for Open…, drag & drop, and Finder/Launch-Services opens).

Signing identity is auto-detected — a "Developer ID Application" certificate if present, otherwise a local "Apple Development" one, otherwise it falls back to ad-hoc (`-`, works locally but isn't trusted by Gatekeeper on other Macs). No identity or Team ID is hardcoded in the script. Override explicitly with:

```sh
MDVIEW_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build-app.sh
```

## Install

Build and copy the app into `/Applications` in one step (also (re)registers it with Launch Services):

```sh
./Scripts/build-app.sh --install
```

Afterwards, mdview is launchable from Spotlight/Launchpad/Dock like any other app, and via `open -a mdview file.md`.

### Making mdview the default app for `.md` files

Once installed, set mdview as the default handler for the `net.daringfireball.markdown` UTI (covers `.md` and `.markdown`) via Finder ("Get Info" > "Open with" > "Change All…" on any `.md` file), or programmatically:

```swift
import AppKit
import UniformTypeIdentifiers

let appURL = URL(fileURLWithPath: "/Applications/mdview.app")
let mdType = UTType("net.daringfireball.markdown")!
try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: mdType)
```

## Uninstall

```sh
./Scripts/uninstall.sh
```

This quits mdview if it's running, removes `/Applications/mdview.app`, unregisters it from Launch Services, and clears its saved preferences (font, colors, appearance mode). If mdview was the default `.md` app, Finder falls back to another handler (or none) automatically once the app is gone.

## Configuration

Open **mdview > Settings…** (Cmd+,):

- **Font tab** — font family, size, and whether headings render bold.
- **Colors tab** — appearance mode (System / Light / Dark), plus a color well per node type and the code block background, editable separately for the light and dark palettes.

Preferences persist across launches and apply to every open window at once.

## Project layout

```
mdview/
  Package.swift
  Scripts/
    build-app.sh        # release build → dist/mdview.app (+ optional --install)
    uninstall.sh          # fully removes mdview (app, LS registration, prefs)
    generate-icon.swift  # regenerates Sources/mdview/Resources/AppIcon.icns
  Sources/mdview/
    mdviewApp.swift      # @main App: DocumentGroup scene + menu commands
    Preferences.swift     # display settings shared by every window, persisted
    Document/              # FileDocument (one per window) + text decoding
    Views/                  # SwiftUI shell (text view, font/color settings)
    Markdown/                # AST → NSAttributedString highlighting engine
    Resources/                # Info.plist, AppIcon.icns, mdview.entitlements
  Fixtures/sample.md    # exercises every supported node type
  Tests/mdviewTests/    # renderer unit tests
```

## Scope

This is a v1 viewer, intentionally scoped:

- App Sandbox is enabled, but no persisted (cross-launch) file-access bookmarks — mdview only keeps access to a file for the session in which it was opened/dropped/selected.
- Not distributed via the Mac App Store; no notarization step in `build-app.sh`.
- No per-language syntax highlighting inside fenced code blocks.
- No image or raw-HTML rendering.
- No file-watching/auto-reload (reopen to refresh).

## License

[MIT](LICENSE)
