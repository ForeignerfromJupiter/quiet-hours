#!/usr/bin/env bash
# Renders the System Settings thumbnails for the five savers from the real renderer:
# launches the Preview app borderless at Apple's thumbnail shape (90:58, as in Random.saver),
# sets a fixed time and the dark finish, captures the window, and scales it to thumbnail.png
# (180×116) and thumbnail@2x.png (360×232) in Resources/Thumbnails/<Style>/. Then run
# `scripts/install-local.sh --refresh-thumbnails`.
# (Checked on macOS 27: a wider 214:130 image gets its sides cropped in the tile; 90:58 shows whole.)
#
#   scripts/make-thumbnails.sh            all five
#   scripts/make-thumbnails.sh Prose      just one
#
# Needs a logged-in GUI session; the first run may ask for Screen Recording permission for the
# terminal. Overwrites the Preview app's own settings (style, finish, time format, seconds).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/Release/QuietHoursPreview.app"
BIN="$APP/Contents/MacOS/QuietHoursPreview"
DOMAIN=com.ashik.quiethours.preview
WORK="$(mktemp -d)"
PID=""
trap '[[ -n "$PID" ]] && kill "$PID" 2>/dev/null; rm -rf "$WORK"' EXIT

# Style | clock time shown | seconds to wait for the style to settle | framing (frame or bleed)
SHOTS=(
  "Hinge 10:10:00 2.5"
  "Chorus 10:10:03 6"
  "Breath 10:10:40 3"
  "Lumen 10:10:00 6"
  "Prose 22:00:00 2.5"
  "Slice 10:10:20 3"
  "Poster 09:41:20 3 bleed"
  "Module 10:10:20 3"
  "Board 10:10:20 3"
  "Specimen 10:10:20 3"
  "Ticker 10:10:20 3"
  "Shutter 10:10:20 3"
  "Echo 10:10:20 3"
)

cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project QuietHours.xcodeproj -scheme QuietHoursPreview -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" -quiet build

# Tiny helper: CGWindowID of the largest on-screen window owned by a given PID.
cat > "$WORK/winid.swift" <<'EOF'
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0["kCGWindowOwnerPID"] as? Int32) == pid }
let best = mine.max { (($0["kCGWindowBounds"] as? [String: Double])?["Width"] ?? 0) < (($1["kCGWindowBounds"] as? [String: Double])?["Width"] ?? 0) }
if let id = best?["kCGWindowNumber"] { print(id) }
EOF
swiftc -O -o "$WORK/winid" "$WORK/winid.swift" 2>/dev/null
swiftc -O -o "$WORK/frame" "$ROOT/scripts/thumbnail-frame.swift" 2>/dev/null

defaults -currentHost write "$DOMAIN" hourCycle h12
defaults -currentHost write "$DOMAIN" showSeconds -bool NO

for shot in "${SHOTS[@]}"; do
  read -r name time wait framing <<<"$shot"
  if [[ $# -gt 0 && "$1" != "$name" ]]; then continue; fi
  style="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
  defaults -currentHost write "$DOMAIN" style "$style"
  defaults -currentHost write "$DOMAIN" "finish.$style" dark

  "$BIN" -QHBare 1240x800 -QHTime "$time" >/dev/null 2>&1 & PID=$!
  sleep "$wait"
  wid=""; for _ in $(seq 1 30); do wid="$("$WORK/winid" "$PID")"; [[ -n "$wid" ]] && break; sleep 0.3; done
  [[ -n "$wid" ]] || { echo "Preview window not found for $name" >&2; exit 1; }
  screencapture -x -o -l "$wid" "$WORK/$name.png"
  kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; sleep 0.8

  out="$ROOT/Resources/Thumbnails/$name"
  mkdir -p "$out"
  # The tile trims a few percent off each side and Hinge/Chorus fill ~94% of the width, so frame
  # the capture at 90% on black with a soft edge (scripts/thumbnail-frame.swift).
  # Poster bleeds off the page by design, so it stays full-bleed.
  if [[ "${framing:-frame}" == bleed ]]; then
    sips -s format png -z 232 360 "$WORK/$name.png" --out "$out/thumbnail@2x.png" >/dev/null
    sips -s format png -z 116 180 "$WORK/$name.png" --out "$out/thumbnail.png" >/dev/null
  else
    "$WORK/frame" "$WORK/$name.png" "$out/thumbnail@2x.png" 360 232
    "$WORK/frame" "$WORK/$name.png" "$out/thumbnail.png" 180 116
  fi
  echo "$name: $out/thumbnail.png, thumbnail@2x.png"
done
