#!/usr/bin/env bash
#
# Build a distributable drag-to-Applications DMG for Audio Extractr.
#
# Usage:   ./scripts/make-dmg.sh
# Output:  dist/AudioExtractr-<version>.dmg   (version from App/project.yml MARKETING_VERSION)
# Needs:   xcodegen, create-dmg   (brew install xcodegen create-dmg)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/App"
BUILD_DIR="$APP_DIR/build/release"
DIST_DIR="$ROOT/dist"

command -v xcodegen   >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)"   >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "error: create-dmg not found (brew install create-dmg)" >&2; exit 1; }

VERSION="$(grep -m1 -E '^[[:space:]]*MARKETING_VERSION:' "$APP_DIR/project.yml" | sed -E 's/.*"([^"]+)".*/\1/')"
echo "==> Building Audio Extractr $VERSION (Release)"

cd "$APP_DIR"
xcodegen
xcodebuild -project AudioExtractr.xcodeproj -scheme AudioExtractr \
  -configuration Release -derivedDataPath build/release \
  -destination 'platform=macOS' clean build

APP="$BUILD_DIR/Build/Products/Release/Audio Extractr.app"
[ -d "$APP" ] || { echo "error: build did not produce $APP" >&2; exit 1; }

mkdir -p "$DIST_DIR"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
cp "$ROOT/ACKNOWLEDGEMENTS.md" "$STAGE/"

DMG="$DIST_DIR/AudioExtractr-$VERSION.dmg"
rm -f "$DMG"

echo "==> Packaging $DMG"
create-dmg \
  --volname "Audio Extractr" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Audio Extractr.app" 150 190 \
  --hide-extension "Audio Extractr.app" \
  --app-drop-link 450 190 \
  --no-internet-enable \
  "$DMG" "$STAGE"

echo "==> Done"
ls -lh "$DMG"
shasum -a 256 "$DMG"
