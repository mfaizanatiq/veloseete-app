#!/usr/bin/env bash
# Upload Veloseete to App Store Connect once the ASC app record exists.
# Same path used for Reakt: xcodebuild -exportArchive with destination=upload
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ARCHIVE="$ROOT/build/Veloseete.xcarchive"
UPLOAD_OPTIONS="$ROOT/tools/testflight/UploadOptions.plist"

if [[ ! -d "$ARCHIVE" ]]; then
  echo "error: missing archive at $ARCHIVE — run archive first"
  exit 1
fi

echo "==> Uploading Veloseete to App Store Connect…"
if xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$UPLOAD_OPTIONS" \
  -allowProvisioningUpdates \
  2>&1 | tee "$ROOT/build/testflight-upload.log"
then
  echo "==> Upload finished. Check TestFlight processing in App Store Connect."
  exit 0
fi

if rg -q "missingApp|Error Downloading App Information" "$ROOT/build/testflight-upload.log"; then
  echo
  echo "App Store Connect app record for com.veloseete.ios is missing."
  echo "Create it once, then re-run this script:"
  echo "  1. Open https://appstoreconnect.apple.com/apps"
  echo "  2. Click + → New App"
  echo "  3. Platforms: iOS"
  echo "  4. Name: Veloseete"
  echo "  5. Bundle ID: com.veloseete.ios"
  echo "  6. SKU: veloseete-ios"
  echo "  7. Re-run: ./tools/testflight/upload.sh"
  open "https://appstoreconnect.apple.com/apps"
  exit 2
fi

exit 1
