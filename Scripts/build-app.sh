#!/bin/bash
# Builds mdview and assembles it into a proper .app bundle so macOS can
# register its document type (.md), show it in the Dock, and let
# `open -a`, double-click, and "Open With" work.
#
# Pass --install to also copy the bundle into /Applications and refresh its
# Launch Services registration there. mdview is registered as the default
# handler for the net.daringfireball.markdown UTI at that /Applications
# path specifically — rebuilding without --install only updates dist/ and
# leaves the registered default app on the previous build until reinstalled.
#
# Signing identity: by default this auto-detects any locally available
# codesigning identity (preferring a distribution-grade "Developer ID
# Application" certificate over a local "Apple Development" one) and never
# hardcodes a specific identity/Team ID in this script, since it's tracked
# in a public repo. Override explicitly with:
#   MDVIEW_SIGN_IDENTITY="Developer ID Application: ..." ./Scripts/build-app.sh
# Falls back to ad-hoc signing (works locally, but Gatekeeper/other Macs
# won't trust it) if no identity is found.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="release"
APP_NAME="mdview"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT_DIR/Sources/mdview/Resources/mdview.entitlements"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Sources/mdview/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Sources/mdview/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

SIGN_IDENTITY="${MDVIEW_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    SIGN_IDENTITY="$(echo "$AVAILABLE_IDENTITIES" | grep -m1 '"Developer ID Application:' | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.*)"$/\1/' || true)"
    if [[ -z "$SIGN_IDENTITY" ]]; then
        SIGN_IDENTITY="$(echo "$AVAILABLE_IDENTITIES" | grep -m1 '"Apple Development:' | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.*)"$/\1/' || true)"
    fi
fi

CODESIGN_ARGS=(--force --deep --entitlements "$ENTITLEMENTS")
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Code signing (sandboxed) with a locally available identity"
    CODESIGN_ARGS+=(--options runtime --sign "$SIGN_IDENTITY")
else
    echo "==> No signing identity found — falling back to ad-hoc signing (sandboxed, local use only)"
    CODESIGN_ARGS+=(--sign -)
fi
codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    INSTALLED_APP="/Applications/$APP_NAME.app"
    echo "==> Installing to $INSTALLED_APP"
    rm -rf "$INSTALLED_APP"
    cp -R "$APP_BUNDLE" "$INSTALLED_APP"
    "$LSREGISTER" -f "$INSTALLED_APP"
    echo "==> Installed and re-registered: $INSTALLED_APP"
fi
