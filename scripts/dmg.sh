#!/usr/bin/env bash
# Package the built .app into a drag-to-install .dmg (app + Applications symlink).
# Dependency-free (hdiutil). Run after build-app.sh, or it builds if needed.
# Usage: scripts/dmg.sh   (SHORT_VERSION inferred from the bundle if unset)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$PROJECT_DIR/LocalDictation.app"
DIST="$PROJECT_DIR/dist"

[[ -d "$APP" ]] || bash "$PROJECT_DIR/scripts/build-app.sh"

VERSION="${SHORT_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.0.0)}"
DMG="$DIST/LocalDictation-$VERSION.dmg"

mkdir -p "$DIST"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/LocalDictation.app"
ln -s /Applications "$STAGE/Applications"   # drag target

# Double-click installer: copies the app to /Applications and strips the
# quarantine flag, so a friend never sees the "damaged" block (which has no
# "Open Anyway"). They right-click → Open this once (scripts get the gentler
# unidentified-developer prompt, unlike unnotarized .app bundles).
cat > "$STAGE/Install Local Dictation.command" <<'CMD'
#!/bin/bash
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/LocalDictation.app"
echo "Installing Local Dictation…"
rm -rf "$DEST"
cp -R "$HERE/LocalDictation.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "Done — launching. You can close this window."
open "$DEST"
CMD
chmod +x "$STAGE/Install Local Dictation.command"

rm -f "$DMG"
hdiutil create -volname "Local Dictation" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
