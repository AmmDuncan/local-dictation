#!/usr/bin/env bash
# Builds the app and produces a distributable zip (+ install notes) in dist/.
# `ditto` preserves the code signature and extended attributes; plain `zip`
# would break the signature.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$PROJECT_DIR/dist"

"$PROJECT_DIR/scripts/build-app.sh"

mkdir -p "$DIST"
rm -f "$DIST/LocalDictation.zip"
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_DIR/LocalDictation.app" "$DIST/LocalDictation.zip"
cp "$PROJECT_DIR/INSTALL.md" "$DIST/INSTALL.md"

SIZE="$(du -h "$DIST/LocalDictation.zip" | cut -f1)"
echo "Packaged → $DIST/LocalDictation.zip ($SIZE)"
echo "Send dist/LocalDictation.zip + dist/INSTALL.md to friends."
