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
SHORT_VERSION="$VERSION" bash "$PROJECT_DIR/scripts/package.sh"

# Stage just the zip and generate a signed appcast whose enclosure points at the
# GitHub release asset URL for this tag.
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$DIST/LocalDictation.zip" "$STAGE/"
"$GEN_APPCAST" "$STAGE" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://github.com/$REPO"

# Publish the release with the zip + appcast attached.
gh release create "$TAG" \
    "$DIST/LocalDictation.zip" \
    "$STAGE/appcast.xml" \
    --repo "$REPO" \
    --title "Local Dictation $VERSION" \
    --notes "Local Dictation $VERSION"

echo "Released $TAG → https://github.com/$REPO/releases/tag/$TAG"
echo "Feed: https://github.com/$REPO/releases/latest/download/appcast.xml"
