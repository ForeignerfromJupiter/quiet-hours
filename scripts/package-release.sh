#!/usr/bin/env bash
# Builds the downloadable release: dist/QuietHours-<version>.zip (+ .sha256) holding the eight
# savers, install instructions and licenses — signed with Developer ID and notarized by Apple,
# so they install with no Gatekeeper warning on any Mac.
#
#   scripts/package-release.sh            full run: archive, sign, notarize, package
#   scripts/package-release.sh --reuse    repackage from the last notarized build (no new upload)
#
# How: Xcode's Developer ID export and notarization only work on app archives, so we archive
# QuietHoursRelease (a packaging-only app carrying the savers in Contents/PlugIns), export it with
# method developer-id + destination upload (Apple's cloud-managed Developer ID certificate, then
# the notary service, both through the developer account signed into Xcode — no passwords or
# keys here), wait for the notarized copy, and lift the savers out of it. Same flow as Ducky's
# release script. Needs: Xcode signed into the HVFYWZDVQH team account.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
STYLES=(Hinge Chorus Breath Lumen Prose Slice Poster Module)
BUILD="$ROOT/build/release"
ARCHIVE="$BUILD/QuietHoursRelease.xcarchive"
DIST="$ROOT/dist"
VERSION="$(awk -F': *' '/MARKETING_VERSION:/ {print $2; exit}' project.yml | tr -d '"')"
NAME="QuietHours-$VERSION"
STAGE="$DIST/stage/Quiet Hours"

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --quiet
CARRIER="$BUILD/notarized/QuietHoursRelease.app"
REUSE=0
[[ "${1:-}" == "--reuse" && -d "$CARRIER" ]] && REUSE=1
[[ $REUSE == 1 ]] || rm -rf "$BUILD"
rm -rf "$DIST/stage" "$DIST/$NAME.zip" "$DIST/$NAME.zip.sha256"
mkdir -p "$BUILD" "$STAGE"

if [[ $REUSE == 0 ]]; then

echo "==> archiving $VERSION (Release, arm64 + x86_64)"
xcodebuild -project QuietHours.xcodeproj -scheme QuietHoursRelease -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$ROOT/build/DerivedData" \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates archive > "$BUILD/archive.log" 2>&1 \
  || { tail -20 "$BUILD/archive.log"; exit 1; }

echo "==> signing with Developer ID and uploading to Apple's notary service"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/export/DeveloperID-notarize.plist \
  -exportPath "$BUILD/notarize-upload" -allowProvisioningUpdates > "$BUILD/notarize-upload.log" 2>&1 \
  || { tail -20 "$BUILD/notarize-upload.log"; exit 1; }

echo "==> waiting for notarization (usually a few minutes)"
for i in $(seq 1 60); do
  rm -rf "$BUILD/notarized"
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$BUILD/notarized" > "$BUILD/notarized.log" 2>&1; then
    break
  fi
  if (( i == 60 )); then echo "notarization not finished after 20 minutes"; tail -20 "$BUILD/notarized.log"; exit 1; fi
  sleep 20
done
fi   # REUSE

echo "==> lifting the notarized savers out"
for s in "${STYLES[@]}"; do
  saver="Quiet Hours – $s.saver"
  ditto "$CARRIER/Contents/PlugIns/$saver" "$STAGE/$saver"
  codesign --verify --strict "$STAGE/$saver"
  info="$(codesign -dv --verbose=2 "$STAGE/$saver" 2>&1)"   # capture first: grep -q + pipefail = false alarms
  [[ "$info" == *"Authority=Developer ID Application"* ]] || { echo "$saver is not signed with Developer ID"; exit 1; }
  # Staple the ticket into the saver itself so it validates offline (best effort).
  xcrun stapler staple "$STAGE/$saver" >/dev/null 2>&1 || echo "   (no stapled ticket for $s: Gatekeeper will check online)"
done

echo "==> Gatekeeper check, as if downloaded"
CHECK="$(mktemp -d)"
ditto "$STAGE/Quiet Hours – Hinge.saver" "$CHECK/Quiet Hours – Hinge.saver"
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$CHECK/Quiet Hours – Hinge.saver"
spctl --assess --type install -vv "$CHECK/Quiet Hours – Hinge.saver" 2>&1 | head -3
spctl --assess --type install "$CHECK/Quiet Hours – Hinge.saver"   # fails the script unless accepted
rm -rf "$CHECK"

cp LICENSE "$STAGE/LICENSE.txt"
cp Resources/Fonts/OFL-Anybody.txt Resources/Fonts/OFL-InstrumentSerif.txt "$STAGE/"
cat > "$STAGE/How to install.txt" <<EOF
Quiet Hours $VERSION: eight calm clock screensavers for macOS 12 and later.

INSTALL
1. Double-click the saver you want, for example "Quiet Hours – Hinge.saver".
2. macOS asks whether to install it for you only or for all users. Pick one.
3. It is now in System Settings → Screen Saver (under "Other"). Click it to use it.
   Install as many as you like: each style is its own tile.

OPTIONS
Click "Options…" next to the selected saver to set the finish (Auto follows light and dark
mode), 12/24-hour time, seconds, and Pure black (on by default, best for OLED screens).

UNINSTALL
Right-click the saver in System Settings → Screen Saver and choose "Delete", or remove it from
~/Library/Screen Savers (or /Library/Screen Savers if you installed it for all users).

Free and open source (MIT): https://github.com/ForeignerfromJupiter/quiet-hours
Fonts: SIL Open Font License, see the OFL files.
EOF

# Strip extended attributes first so the zip has no "._" sidecar entries.
xattr -cr "$STAGE"
(cd "$DIST/stage" && ditto -c -k --norsrc --keepParent "Quiet Hours" "$DIST/$NAME.zip")
(cd "$DIST" && shasum -a 256 "$NAME.zip" | tee "$NAME.zip.sha256")
echo "Done: $DIST/$NAME.zip"
