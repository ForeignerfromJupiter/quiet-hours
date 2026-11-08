#!/usr/bin/env bash
# Builds QuietHours.saver (Release, universal) and installs it into ~/Library/Screen Savers.
#
#   scripts/install-local.sh            build + install
#   scripts/install-local.sh --open     … then open the Screen Saver settings pane
#   scripts/install-local.sh --uninstall
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Library/Screen Savers"
NAME="QuietHours.saver"
DERIVED="$ROOT/build/DerivedData"

restart_host() {
  # The host caches the loaded bundle; kill it so the next start loads the new copy.
  killall legacyScreenSaver 2>/dev/null || true
  killall "legacyScreenSaver (Wallpaper)" 2>/dev/null || true
}

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$DEST/$NAME"
  restart_host
  echo "Removed $DEST/$NAME"
  exit 0
fi

cd "$ROOT"
if ! command -v xcodegen >/dev/null; then
  echo "Installing XcodeGen with Homebrew…"
  brew install xcodegen
fi
xcodegen generate --quiet

echo "Building $NAME (Release, arm64 + x86_64)…"
xcodebuild -project QuietHours.xcodeproj -scheme QuietHours -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build

BUILT="$DERIVED/Build/Products/Release/$NAME"
[[ -d "$BUILT" ]] || { echo "Build output not found at $BUILT" >&2; exit 1; }

mkdir -p "$DEST"
rm -rf "$DEST/$NAME"
ditto "$BUILT" "$DEST/$NAME"
restart_host

echo "Installed $DEST/$NAME"
echo "  archs: $(lipo -archs "$DEST/$NAME/Contents/MacOS/QuietHours")"
echo "  Choose it in System Settings → Screen Saver (it's under Other)."

if [[ "${1:-}" == "--open" ]]; then
  open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
fi
