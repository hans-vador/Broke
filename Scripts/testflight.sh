#!/bin/zsh
#
# Build the shipped app and upload it to TestFlight.
#
#   Scripts/testflight.sh              # build number = current UTC timestamp
#   Scripts/testflight.sh 42           # explicit build number
#   Scripts/testflight.sh 42 --dry-run # archive + export, stop before upload
#
# Every upload needs a build number App Store Connect has never seen, so the
# default is a UTC timestamp (YYYYMMDDHHMM) — always unique, always ascending.
# The marketing version (1.0) is what testers see and only changes when you
# decide it does.
#
# Credentials: App Store Connect API key, via either
#   - env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (path to AuthKey_XXX.p8), or
#   - a key placed in ~/.appstoreconnect/private_keys/ (altool finds it by ID)
# An API key is preferred over an Apple ID + app-specific password: it doesn't
# expire on password changes and doesn't trip 2FA.

set -euo pipefail

SCHEME="Broke Shipped"
CONFIG="Release"
ROOT="${0:A:h:h}"
BUILD="${1:-$(date -u +%Y%m%d%H%M)}"
DRY_RUN="${2:-}"
OUT="$ROOT/build/testflight"
ARCHIVE="$OUT/Broke.xcarchive"
EXPORT="$OUT/export"

echo "==> Broke → TestFlight"
echo "    scheme:  $SCHEME ($CONFIG)"
echo "    build:   $BUILD"
echo "    root:    $ROOT"

rm -rf "$OUT"; mkdir -p "$OUT"

# The dev tooling is checked for on the built binary further down rather than by
# pattern-matching project.pbxproj — Xcode rewrites that file freely (quoting and
# ordering both change), so a text heuristic there gives false results in both
# directions. Inspect the artifact, not a proxy for it.

echo "==> Archiving"
xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  -allowProvisioningUpdates \
  archive

APP="$ARCHIVE/Products/Applications/Broke.app"

echo "==> Verifying the archive is a real shipping build"
fail=0
# NB: count matches instead of `grep -q`. Under `set -o pipefail`, `grep -q`
# exits on the first match, `strings` then dies of SIGPIPE, and the whole
# pipeline reports failure — which reads as "no match" and would hide a real
# leak. Materialise the strings once and grep that.
SYMS="$OUT/shipped-strings.txt"
strings -a "$APP/Broke" > "$SYMS"

# The dev panel must be absent. These needles are >15 bytes on purpose: Swift
# packs shorter literals into immediates where `strings` cannot see them, so a
# short needle would "pass" whether or not the code was there.
for needle in "Reset onboarding & lock mode" "Simulate pod: in range" "devNFCTestBypass"; do
  if [ "$(grep -cF -- "$needle" "$SYMS" || true)" -gt 0 ]; then
    echo "   !! dev tooling leaked into the shipped binary: $needle"; fail=1
  fi
done
# Positive control: proves the check can actually see strings in this binary.
if [ "$(grep -cF -- "Stick the tag somewhere annoying" "$SYMS" || true)" -eq 0 ]; then
  echo "   !! leak check is broken (positive control missing) — not trusting it"; fail=1
fi
# An icon is mandatory; App Store Connect rejects builds without one.
if ! xcrun assetutil --info "$APP/Assets.car" 2>/dev/null | grep -qi AppIcon; then
  echo "   !! no AppIcon in Assets.car"; fail=1
fi
[ "$fail" -eq 0 ] || { echo "==> Refusing to upload."; exit 1; }
echo "    clean: no dev tooling, icon present"

echo "==> Exporting for App Store Connect"
cat > "$OUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>8MSX699Z2T</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates

IPA=$(ls "$EXPORT"/*.ipa | head -1)
echo "    exported: $IPA"

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "==> Dry run: stopping before upload."
  exit 0
fi

echo "==> Uploading to TestFlight"
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
else
  echo "!! Set ASC_KEY_ID and ASC_ISSUER_ID (App Store Connect API key)."
  echo "   The .ipa is ready at: $IPA"
  echo "   You can also drag it into Transporter.app to upload by hand."
  exit 1
fi

echo "==> Done. Processing takes a few minutes before it appears in TestFlight."
