#!/bin/bash
# Completely removes mdview from the system: quits the running app, deletes
# /Applications/mdview.app, unregisters it from Launch Services, and clears
# its persisted preferences (font, colors, appearance mode, etc).
set -euo pipefail

APP_NAME="mdview"
BUNDLE_ID="com.papalma.mdview"
INSTALLED_APP="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Quitting $APP_NAME if running"
pkill -f "$INSTALLED_APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true

if [[ -d "$INSTALLED_APP" ]]; then
    echo "==> Unregistering from Launch Services"
    "$LSREGISTER" -u "$INSTALLED_APP" 2>/dev/null || true

    echo "==> Removing $INSTALLED_APP"
    rm -rf "$INSTALLED_APP"
else
    echo "==> $INSTALLED_APP not found, skipping"
fi

echo "==> Clearing preferences ($BUNDLE_ID)"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo "==> Done. mdview has been fully uninstalled."
echo "    Note: if mdview was set as the default app for .md/.markdown files,"
echo "    Finder will fall back to another handler (or none) automatically."
