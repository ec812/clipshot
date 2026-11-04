#!/usr/bin/env bash
#
# Local install: build Release and install Clipshot.app to ~/Applications.
#
# Signing comes from the project settings (Apple Development, team 7A7G3458QV)
# and the single codesigning identity in the keychain — no overrides passed.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
BUILT_APP="$BUILD_DIR/Build/Products/Release/Clipshot.app"
INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/Clipshot.app"

mkdir -p "$BUILD_DIR"

echo "==> Release build"
xcodebuild \
  -project "$ROOT/Clipshot.xcodeproj" \
  -scheme Clipshot \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build did not produce $BUILT_APP" >&2
  exit 1
fi

echo "==> Install to $APP"
mkdir -p "$INSTALL_DIR"
rm -rf "$APP"
ditto "$BUILT_APP" "$APP"

echo "==> Signature summary"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Format|Authority|TeamIdentifier|Signature|Timestamp)=' || true

echo
echo "Installed: $APP"
