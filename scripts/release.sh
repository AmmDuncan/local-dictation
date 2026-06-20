#!/usr/bin/env bash
# Cut a release: build + package the signed app, generate a signed Sparkle
# appcast, and publish a GitHub release with the zip + appcast.xml attached.
# The app's SUFeedURL points at the latest-release permalink for appcast.xml,
# so publishing a release is what makes the update go live.
#
# Usage: scripts/release.sh v0.1.1
set -euo pipefail

TAG="${1:?usage: release.sh <tag, e.g. v0.1.1>}"
VERSION="${TAG#v}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="AmmDuncan/local-dictation"
DIST="$PROJECT_DIR/dist"
STAGE="$PROJECT_DIR/.build/appcast-stage"
GEN_APPCAST="$(find "$PROJECT_DIR/.build/artifacts" -name generate_appcast -type f 2>/dev/null | head -1)"

if [[ -z "$GEN_APPCAST" ]]; then
    echo "FATAL: generate_appcast not found — run 'swift build' first to resolve Sparkle." >&2
    exit 1
fi

# Build + package the signed app. SHORT_VERSION drives CFBundleShortVersionString;
# CFBundleVersion is the commit count (monotonic, drives Sparkle's comparison).
# Pass DEVELOPER_ID_IDENTITY through so the notarization path (build-app.sh) can
# sign with a Developer ID + hardened runtime when notarizing.
SHORT_VERSION="$VERSION" bash "$PROJECT_DIR/scripts/package.sh"

# Notarize (opt-in): needs a paid Apple Developer account. Set NOTARY_PROFILE to
# a stored notarytool keychain profile (`xcrun notarytool store-credentials`) AND
# build with DEVELOPER_ID_IDENTITY so the app is Developer-ID + hardened-runtime
# signed. When unset we skip — friends right-click-Open (the current default).
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "Notarizing → submitting to Apple (profile '$NOTARY_PROFILE')…"
    xcrun notarytool submit "$DIST/LocalDictation.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$PROJECT_DIR/LocalDictation.app"
    # Re-zip so the published archive carries the stapled ticket.
    ( cd "$PROJECT_DIR" && ditto -c -k --keepParent "LocalDictation.app" "$DIST/LocalDictation.zip" )
    echo "Notarized + stapled."
else
    echo "Skipping notarization (NOTARY_PROFILE unset) — self-signed distribution (right-click-Open)."
fi

# Stage just the zip and generate a signed appcast whose enclosure points at the
# GitHub release asset URL for this tag. (Sparkle auto-update uses the zip.)
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$DIST/LocalDictation.zip" "$STAGE/"
"$GEN_APPCAST" "$STAGE" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://github.com/$REPO"

# Also build a drag-to-install .dmg for manual download (friendlier than the zip).
SHORT_VERSION="$VERSION" bash "$PROJECT_DIR/scripts/dmg.sh"
DMG="$DIST/LocalDictation-$VERSION.dmg"

# Publish the release with the dmg (manual install) + zip + appcast (auto-update).
# Notes go through a file (--notes-file) to avoid shell-quoting pitfalls; plain
# text only (no backticks) so nothing is interpreted by the shell.
NOTES_FILE="$DIST/release-notes.md"
cat > "$NOTES_FILE" <<NOTE
**Install (Apple Silicon, macOS 14+):**

1. Download **LocalDictation-$VERSION.dmg** and open it.
2. Right-click **"Install Local Dictation.command"** -> Open -> Open. It installs the app and launches it.

A plain double-click is blocked as "damaged" because this app isn't notarized by Apple — the installer clears that for you. (By hand: drag the app into Applications, then in Terminal run:  xattr -dr com.apple.quarantine /Applications/LocalDictation.app )

Then grant Microphone + Accessibility, download a model in Settings -> Models, and hold Control+Space to dictate. Full guide: INSTALL.md.
NOTE
gh release create "$TAG" \
    "$DMG" \
    "$DIST/LocalDictation.zip" \
    "$PROJECT_DIR/INSTALL.md" \
    "$STAGE/appcast.xml" \
    --repo "$REPO" \
    --title "Local Dictation $VERSION" \
    --notes-file "$NOTES_FILE"

echo "Released $TAG → https://github.com/$REPO/releases/tag/$TAG"
echo "Feed: https://github.com/$REPO/releases/latest/download/appcast.xml"
