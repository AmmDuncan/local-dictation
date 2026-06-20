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
# quarantine flag macOS puts on downloads, so the unnotarized app opens without
# the Gatekeeper "could not verify" block. They right-click → Open this once
# (scripts still get the gentler prompt on macOS 15+, unlike .app bundles which
# only offer "Done" and must go through System Settings → Open Anyway).
cat > "$STAGE/Install Local Dictation.command" <<'CMD'
#!/bin/bash
# Installs Local Dictation to /Applications and clears the quarantine flag so the
# (unnotarized) app launches without the Gatekeeper block. Right-click → Open this
# file rather than double-clicking, so macOS lets the script run.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/LocalDictation.app"
DEST="/Applications/LocalDictation.app"

pause() { echo; read -n 1 -s -r -p "Press any key to close this window."; echo; }

echo "Installing Local Dictation…"
if [[ ! -d "$SRC" ]]; then
  echo "ERROR: LocalDictation.app isn't next to this installer."
  echo "Open the .dmg first, then run this from inside it."
  pause; exit 1
fi

# Quit any running copy so the bundle isn't in use while we replace it.
osascript -e 'quit app "LocalDictation"' 2>/dev/null || true
pkill -x LocalDictation 2>/dev/null || true

rm -rf "$DEST"
if ! cp -R "$SRC" "$DEST"; then
  echo "ERROR: couldn't copy to /Applications (need an admin account)."
  echo "Drag LocalDictation.app into Applications manually, then re-run this."
  pause; exit 1
fi

# Strip every quarantine/provenance attr macOS added to the download.
xattr -cr "$DEST" 2>/dev/null || true
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "Installed to /Applications. Launching…"
if open "$DEST" 2>/dev/null; then
  echo "✅ Done — Local Dictation is launching."
else
  echo "Installed, but macOS blocked the first launch. Open it once via:"
  echo "  System Settings → Privacy & Security → scroll down → Open Anyway"
fi
pause
CMD
chmod +x "$STAGE/Install Local Dictation.command"

rm -f "$DMG"
hdiutil create -volname "Local Dictation" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
