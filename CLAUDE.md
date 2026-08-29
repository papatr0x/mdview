# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

mdview is a native macOS Markdown **viewer** — not an editor, not a WYSIWYG/HTML-style renderer. It displays the raw Markdown source verbatim (`#`, `>`, `**`, backticks, etc. all stay visible) and applies syntax-highlight coloring per node type on top of it, the way a code editor colorizes source rather than the way a browser renders HTML. Read-only and scrollable, one window per open document.

**The one sanctioned exception to "verbatim" is ordered-list numerals.** CommonMark reads only the *first* item's number (it sets where the list starts) and ignores every one after it, so a list written entirely as `1.` is valid markdown that renders as a column of `1.`s — unreadable as a list. mdview shows each item's real position instead, behind the "Renumber ordered lists" setting (default on; off restores a strictly verbatim view). This is the *only* place the source text is altered, and any new feature that wants to alter text should be weighed against that.

**Hiding the emphasis markers is deliberately *not* a second exception.** The `**`, `*` and `_` around bold and italic text are not drawn, but they are still in the string: the renderer marks them with an `.hiddenMarkdownDelimiter` attribute and `AppearanceAwareTextView`, as the layout manager's delegate, gives those characters a `.null` glyph — no drawing, no width, character untouched. Deleting them would have been less code and was rejected for exactly this reason: copying a bold phrase out of the view still yields the `**` the file has, and every range the plan recorded still lines up with the source. Reach for the same trick before reaching for `replaceCharacters`.

## Commands

```sh
swift build -c release          # compile
swift test                      # run all tests
swift test --filter <TestName>  # run a single test, e.g. testHeadingIsBoldAndColored
```

There is no `.xcodeproj` — this is a pure Swift Package Manager project. `swift build` alone produces a bare executable, not something Finder/Launch Services can treat as a real app.

### Packaging, installing, uninstalling

```sh
./Scripts/build-app.sh            # release build → dist/mdview.app (signed, sandboxed)
./Scripts/build-app.sh --install  # also copies to /Applications, re-registers with Launch Services
./Scripts/uninstall.sh            # quits the app, removes it, unregisters it, clears UserDefaults prefs
```

`build-app.sh` auto-detects a local codesigning identity (Developer ID Application > Apple Development > ad-hoc `-` fallback) via `security find-identity` — **never hardcode a specific identity, Team ID, or personal info in this script or in commits**; this repo is public. Override with `MDVIEW_SIGN_IDENTITY=... ./Scripts/build-app.sh` if needed.

**After any code change, the expected loop is: `swift build` → `swift test` → `./Scripts/build-app.sh --install` → relaunch and smoke-test** (`open -a /Applications/mdview.app <file>`, check `pgrep`, check `log show --predicate 'process == "mdview"'` for crashes/sandbox denials). For visual/UI changes, actually render and look at the result rather than assuming the code is correct — several past bugs here (code-block background geometry, a keyboard-shortcut mismatch, a Settings-window sizing glitch) compiled fine but were behaviorally/visually wrong.

`Scripts/generate-icon.swift` (run with `swift Scripts/generate-icon.swift`) regenerates `Sources/mdview/Resources/AppIcon.icns` programmatically (no external image assets/design tool involved).

## Architecture

**Rendering pipeline is range-based, not tree-reconstruction-based.** `MarkdownRenderer` (`Sources/mdview/Markdown/MarkdownRenderer.swift`) parses the document with Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown), then a `MarkupVisitor` walks the AST and, for each node, maps its `Markup.range` (line/column) to an `NSRange` in the *original* source string and overlays color/font/trait attributes onto that exact range of an `NSMutableAttributedString` seeded with the verbatim source text. Nothing is stripped or reflowed — this is the core design constraint and the reason the renderer looks different from a typical Markdown-to-HTML converter.

**Styling is centralized in `MarkdownStyle`** (`Sources/mdview/Markdown/MarkdownStyle.swift`), which resolves a `ColorTheme` + font preference + light/dark appearance into concrete `NSFont`/`NSColor` per `MarkdownNodeKind` (`Sources/mdview/Markdown/ColorTheme.swift`). There are two user-chosen fonts, each with its own family and size: a body font for everything that is not code, and a code font for inline code and fenced blocks, which the settings restrict to fixed-width families (the body font has no such restriction, so a proportional body font is allowed and does break the column alignment of markers and indentation). Beyond that split, only color and — for a few kinds — weight/slant differ. An unavailable code family falls back to the system monospaced font, which is what code used unconditionally before the family became configurable. The list-item spacing is the only thing that sets `NSParagraphStyle`, and it sets it on the item's *first line* only — note that `addAttribute(.paragraphStyle:)` replaces the whole paragraph style rather than merging into it, so a second paragraph-level attribute would have to build on this one instead of overwriting it. `ColorTheme` holds two full `ColorPalette`s (light/dark), each mapping every `MarkdownNodeKind` to a color plus a dedicated code-block background color, and is `Codable`/persisted as JSON in `UserDefaults`.

**Fenced code blocks get a manually-drawn full-width background.** `NSAttributedString.backgroundColor` only fills each line's actual glyph width, so a short line (like a closing ` ``` `) renders narrower than the content lines above it. `AppearanceAwareTextView` (`Sources/mdview/Views/DocumentTextView.swift`) works around this by enumerating `.backgroundColor` attribute runs and filling each line itself from inside `drawBackground(in:)`, producing a uniform block regardless of AppKit's per-glyph fill behavior. It takes the *width* from the line-fragment rect and the *height* from the used rect: the fragment also contains any paragraph spacing above the line, and filling that painted the gap a list item reserves above a fenced block that opens it.

**State is split by what it belongs to.** `Preferences` (`Sources/mdview/Preferences.swift`) is a single `@Observable` singleton holding only what every window shares — the two fonts, color theme, list spacing, the two toggles, appearance mode — and persisting each through an injectable `UserDefaults`. Document state is per window: `DocumentGroup(viewing:)` in `mdviewApp.swift` gives each file its own `MarkdownDocument`, `ContentView`, and `StylePlanCache`. `DocumentGroup` also routes every way of opening a file — Finder double-click, "Open With", `open`, the Open panel — so there is no app delegate; drag & drop is the one path handled by hand, in `ContentView.handleDrop`, which hands the URL to `NSDocumentController` so a dropped file opens in its own window rather than replacing what is on screen.

**Rendering is split into plan and paint, and the plan runs off the main thread.** `MarkdownRenderer.plan(for:)` does the expensive half — parse, walk, map every range — and depends only on the text; `render(plan:markdown:style:)` resolves colors and fonts onto it and depends only on the style. `StylePlanCache` (`Sources/mdview/Markdown/StylePlanCache.swift`) holds one window's plan so a preference change repaints without re-parsing, and parses on a detached task so a window can appear before its document is highlighted. Painting stays on the main actor — it touches `NSFont`/`NSColor` and view state — while a plan already in hand comes back synchronously, which is what keeps a continuous color-well drag repainting on every mouse event.

**Appearance is user-overridable, independent of the OS.** `AppearanceMode` (System/Light/Dark) sets `NSApp.appearance` directly, from `Preferences.applyAppearance()`; the render path reads back `NSApp.effectiveAppearance` to decide which `ColorPalette` to apply, so the override and the system-following default share one code path.

**App Sandbox is enabled** (`Sources/mdview/Resources/mdview.entitlements`: `app-sandbox` + `files.user-selected.read-only`). This covers Open panel, drag & drop, and Launch Services opens without needing persisted security-scoped bookmarks, but access does *not* survive across relaunches for a given file — that's an intentional v1 limitation, not a bug.

**Document-type registration** (`Sources/mdview/Resources/Info.plist`) uses the community `net.daringfireball.markdown` UTI with `LSHandlerRank = Alternate` (won't silently hijack another app's default-app status; must be set explicitly, e.g. via Finder "Get Info" or `NSWorkspace.setDefaultApplication(at:toOpen:)`).

## Testing

`Tests/mdviewTests/MarkdownRendererTests.swift` asserts on real `NSAttributedString` attributes/ranges (colors, font traits, background ranges) for hand-written Markdown snippets — not just "does it compile." `Fixtures/sample.md` exercises every supported node type and is also used as the manual-launch smoke-test file. When adding a new node-type behavior, follow the existing pattern: render a minimal snippet, assert on the attribute at the relevant character index.
