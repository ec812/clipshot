#!/usr/bin/env bash
#
# Release packaging for direct (notarized) distribution.
#
# Nothing here runs without your own Apple Developer credentials. With no
# credentials the script performs a Release build only and tells you what is
# missing; it never fabricates a signature or notarization ticket.
#
# Required for full packaging:
#   DEVELOPMENT_TEAM           e.g. ABCDE12345
#   DEVELOPER_ID_APPLICATION   e.g. "Developer ID Application: Your Name (ABCDE12345)"
# Required for notarization:
#   APPLE_ID
#   APPLE_APP_PASSWORD         app-specific password
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/Clipshot.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Clipshot.app"
DMG="$BUILD_DIR/Clipshot.dmg"
ZIP="$BUILD_DIR/Clipshot.zip"

mkdir -p "$BUILD_DIR"

echo "==> Release build"
xcodebuild \
  -project "$ROOT/Clipshot.xcodeproj" \
  -scheme Clipshot \
  -configuration Release \
  -destination 'platform=macOS' \
  build

if [[ -z "${DEVELOPMENT_TEAM:-}" || -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  cat <<'EOF'

Release build succeeded.

Signing/export/notarization skipped because DEVELOPMENT_TEAM and/or
DEVELOPER_ID_APPLICATION are not set. Re-run with:

  DEVELOPMENT_TEAM=ABCDE12345 \
  DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (ABCDE12345)" \
  APPLE_ID="you@example.com" \
  APPLE_APP_PASSWORD="app-specific-password" \
  ./Scripts/package.sh

EOF
  exit 0
fi

echo "==> Archive"
xcodebuild \
  -project "$ROOT/Clipshot.xcodeproj" \
  -scheme Clipshot \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  CODE_SIGN_STYLE=Manual \
  archive

echo "==> Export Developer ID app"
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>teamID</key>
    <string>${DEVELOPMENT_TEAM}</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

if [[ ! -d "$APP" ]]; then
  echo "Export did not produce $APP" >&2
  exit 1
fi

echo "==> Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP" || true

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "==> Notarize"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$DEVELOPMENT_TEAM" \
    --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
else
  echo "Skipping notarization (APPLE_ID / APPLE_APP_PASSWORD not set)."
fi

echo "==> Create DMG"
rm -f "$DMG"
hdiutil create \
  -volname "Clipshot" \
  -srcfolder "$APP" \
  -ov \
  -format UDZO \
  "$DMG"

echo
echo "Done:"
echo "  App: $APP"
echo "  DMG: $DMG"
