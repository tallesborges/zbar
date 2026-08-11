#!/usr/bin/env bash
# Builds zbar and packages it into a signed .app bundle at build/zbar.app.
# A real bundle is required: LSUIElement (menu-bar-only) is read from Info.plist,
# and the Accessibility permission zbar will need later is granted per code
# signature, so `swift run` on the bare binary won't do.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/zbar.app"

echo "▶ swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/zbar"

echo "▶ assembling $APP"
# Only Contents is recreated; keeping the .app directory itself preserves the
# inode that TCC (and Dock/Finder bookmarks) resolve through. Deleting the whole
# bundle makes macOS treat every build as a brand-new app and re-prompt for
# permissions.
mkdir -p "$APP"
rm -rf "$APP/Contents"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/zbar"
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"

# SwiftPM resource bundles (highlight.js for the Markdown renderer). Bundle.module
# resolves these through the main bundle's resource directory.
for bundle in "$(dirname "$BIN")"/*.bundle; do
    [ -e "$bundle" ] || continue
    echo "▶ bundling $(basename "$bundle")"
    cp -R "$bundle" "$APP/Contents/Resources/"
done

echo "▶ code signing"
# A stable signing identity keeps TCC grants across rebuilds; ad-hoc signatures
# change their cdhash every build and re-trigger every prompt. Match on the
# certificate name rather than taking the first identity, which may be neither.
IDENTITY=${ZBAR_CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}
if [ -z "$IDENTITY" ]; then
    echo "  ⚠ no stable identity found — falling back to ad-hoc (permissions will reset each build)"
    IDENTITY="-"
else
    echo "  using identity: $IDENTITY"
fi

codesign --force --deep --sign "$IDENTITY" --options runtime "$APP"

echo "✓ built $APP"
echo "  open it with:  open \"$APP\""
