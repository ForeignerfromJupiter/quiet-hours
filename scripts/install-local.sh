#!/usr/bin/env bash
# Builds the five Quiet Hours savers (Release, universal) and installs them into
# ~/Library/Screen Savers, one tile per style in System Settings → Screen Saver.
#
#   scripts/install-local.sh            build + install all five
#   scripts/install-local.sh --open     … then open the Screen Saver settings pane
#   scripts/install-local.sh --uninstall
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Library/Screen Savers"
DERIVED="$ROOT/build/DerivedData"
STYLES=(Hinge Chorus Breath Lumen Prose)

restart_host() {
  # The host caches loaded bundles; kill it so the next start loads the new copies.
  killall legacyScreenSaver 2>/dev/null || true
  killall "legacyScreenSaver (Wallpaper)" 2>/dev/null || true
}

remove_installed() {
  for s in "${STYLES[@]}"; do rm -rf "$DEST/Quiet Hours – $s.saver"; done
  rm -rf "$DEST/QuietHours.saver"   # the earlier all-in-one bundle
}

if [[ "${1:-}" == "--uninstall" ]]; then
  remove_installed
  restart_host
  echo "Removed Quiet Hours from $DEST"
  exit 0
fi

cd "$ROOT"
if ! command -v xcodegen >/dev/null; then
  echo "Installing XcodeGen with Homebrew…"
  brew install xcodegen
fi
xcodegen generate --quiet

echo "Building ${#STYLES[@]} savers (Release, arm64 + x86_64)…"
xcodebuild -project QuietHours.xcodeproj -scheme Savers -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build

mkdir -p "$DEST"
remove_installed
for s in "${STYLES[@]}"; do
  name="Quiet Hours – $s.saver"
  built="$DERIVED/Build/Products/Release/$name"
  [[ -d "$built" ]] || { echo "Build output not found: $built" >&2; exit 1; }
  ditto "$built" "$DEST/$name"
  echo "Installed $name ($(lipo -archs "$DEST/$name/Contents/MacOS/Quiet Hours – $s"))"
done
restart_host
echo "Pick one in System Settings → Screen Saver (under Other)."

if [[ "${1:-}" == "--open" ]]; then
  open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
fi
