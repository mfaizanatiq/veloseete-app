#!/usr/bin/env bash
# Archive Veloseete for App Store Connect / TestFlight (automatic signing).
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SCHEME="Veloseete"
PROJECT="Veloseete.xcodeproj"
TEAM="X978QRK3WP"
DERIVED="$ROOT/build/TestFlightDerivedData"
ARCHIVE="$ROOT/build/Veloseete.xcarchive"
EXPORT_DIR="$ROOT/build/TestFlightExport"
EXPORT_OPTIONS="$ROOT/tools/testflight/ExportOptions.plist"

if [[ ! -f "Veloseete/GoogleService-Info.plist" ]]; then
  echo "error: Veloseete/GoogleService-Info.plist missing — required for Release."
  exit 1
fi

echo "==> Cleaning previous archive/export"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$ROOT/build"

echo "==> Archiving (Release, team $TEAM)"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic

echo "==> Exporting IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

IPA="$(find "$EXPORT_DIR" -name '*.ipa' | head -1)"
if [[ -z "${IPA:-}" ]]; then
  echo "error: no IPA exported"
  exit 1
fi

echo "==> IPA ready: $IPA"
echo
echo "Upload options:"
echo "  1) Open Xcode → Organizer → Distribute App"
echo "  2) open -a Transporter \"$IPA\""
echo "  3) With App Store Connect API key:"
echo "       xcrun altool --upload-app -f \"$IPA\" -t ios --apiKey KEY --apiIssuer ISSUER"
echo
echo "After upload: App Store Connect → TestFlight → wait for processing → add testers."
