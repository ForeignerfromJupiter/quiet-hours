#!/usr/bin/env bash
# Builds the downloadable release: dist/QuietHours-<version>.zip, holding the eight savers,
# install instructions and the licenses.
#
#   scripts/package-release.sh
#
# Signing, best available:
#   1. "Developer ID Application" certificate in your keychain → signed for distribution
#      (hardened runtime, secure timestamp). Required for other people's Macs to accept it.
#   2. Otherwise the Apple Development signature from the normal build is kept, and the zip is
#      marked as a local test build: it works on this Mac, but Gatekeeper blocks it elsewhere.
#
# Notarization (only with Developer ID): if a notarytool keychain profile named "quiethours"
# exists, the zip is submitted to Apple and the result is stapled to each saver. Create it once:
#   xcrun notarytool store-credentials quiethours --apple-id <you@example.com> --team-id HVFYWZDVQH
# (it asks for an app-specific password from appleid.apple.com; nothing is stored in the repo).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
STYLES=(Hinge Chorus Breath Lumen Prose Slice Poster Module)
PROFILE="${NOTARY_PROFILE:-quiethours}"

cd "$ROOT"
VERSION="$(awk -F': *' '/MARKETING_VERSION:/ {print $2; exit}' project.yml | tr -d '"')"
NAME="QuietHours-$VERSION"
STAGE="$DIST/stage/Quiet Hours"

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --quiet
echo "Building ${#STYLES[@]} savers $VERSION (Release, arm64 + x86_64)…"
xcodebuild -project QuietHours.xcodeproj -scheme Savers -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build

rm -rf "$DIST/stage" "$DIST/$NAME.zip"
mkdir -p "$STAGE"
for s in "${STYLES[@]}"; do
  ditto "$DERIVED/Build/Products/Release/Quiet Hours – $s.saver" "$STAGE/Quiet Hours – $s.saver"
done

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
if [[ -n "$IDENTITY" ]]; then
  echo "Signing with: $IDENTITY"
  for s in "${STYLES[@]}"; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$STAGE/Quiet Hours – $s.saver"
  done
  DISTRIBUTABLE=1
else
  echo "⚠︎  No 'Developer ID Application' certificate found: keeping the Apple Development signature."
  echo "   This zip works on this Mac only; other Macs will block it. See the header of this script."
  DISTRIBUTABLE=0
fi
for s in "${STYLES[@]}"; do codesign --verify --strict "$STAGE/Quiet Hours – $s.saver"; done

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

Free and open source (MIT). Fonts: SIL Open Font License, see the OFL files.
EOF
if [[ "$DISTRIBUTABLE" == 0 ]]; then
  printf '\nNOTE: this is a local test build, not signed for distribution.\n' >> "$STAGE/How to install.txt"
fi

# Strip extended attributes first so the zip has no "._" sidecar entries.
zip_it() { xattr -cr "$STAGE"; (cd "$DIST/stage" && ditto -c -k --norsrc --keepParent "Quiet Hours" "$DIST/$NAME.zip"); }
zip_it

if [[ "$DISTRIBUTABLE" == 1 ]] && xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "Notarizing $NAME.zip with Apple (usually a few minutes)…"
  xcrun notarytool submit "$DIST/$NAME.zip" --keychain-profile "$PROFILE" --wait
  # Staple the ticket into each saver so it validates offline, then re-zip.
  for s in "${STYLES[@]}"; do xcrun stapler staple "$STAGE/Quiet Hours – $s.saver" || true; done
  rm -f "$DIST/$NAME.zip"; zip_it
  spctl --assess --type install -vv "$STAGE/Quiet Hours – Hinge.saver" || true
elif [[ "$DISTRIBUTABLE" == 1 ]]; then
  echo "⚠︎  Signed but not notarized: no notarytool profile '$PROFILE'. See the header of this script."
fi

shasum -a 256 "$DIST/$NAME.zip" | tee "$DIST/$NAME.zip.sha256"
echo "Done: $DIST/$NAME.zip"
