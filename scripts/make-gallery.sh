#!/usr/bin/env bash
# Renders the README gallery from the real renderer (via the Preview app, borderless):
#   docs/images/<style>-dark.png, <style>-light.png   stills, 1200 px wide
#   docs/images/<style>.gif                            the style's minute change, dark, 600 px wide
#
#   scripts/make-gallery.sh             every style
#   scripts/make-gallery.sh Hinge Prose only these
#
# Needs a logged-in GUI session and Screen Recording permission for the terminal, plus ffmpeg
# (brew install ffmpeg). Overwrites the Preview app's own settings while it runs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="$ROOT/build/DerivedData"
BIN="$DERIVED/Build/Products/Release/QuietHoursPreview.app/Contents/MacOS/QuietHoursPreview"
DOMAIN=com.ashik.quiethours.preview
OUT="$ROOT/docs/images"
WORK="$(mktemp -d)"
PID=""
trap '[[ -n "$PID" ]] && kill "$PID" 2>/dev/null; rm -rf "$WORK"' EXIT
command -v ffmpeg >/dev/null || { echo "ffmpeg is required: brew install ffmpeg" >&2; exit 1; }

# Style | still time | GIF start time (a change lands ~2 s in) | settle seconds
SHOTS=(
  "Hinge 10:10:20 10:09:58 2.5"
  "Chorus 10:10:05 10:09:58 6"
  "Breath 10:10:42 10:09:58 3"
  "Lumen 10:10:20 10:09:58 6"
  "Prose 22:00:10 20:07:58 2.5"
  "Slice 10:10:20 10:09:58 3"
  "Poster 09:41:20 09:59:58 3"
  "Module 10:10:20 10:09:58 3"
  "Ticker 10:10:20 10:09:58 3"
  "Echo 10:10:20 10:09:58 3"
  "Shutter 10:10:20 10:09:58 3"
  "Specimen 10:10:20 10:09:58 3"
  "Board 10:10:20 10:09:58 3"
)

xcodegen generate --quiet
xcodebuild -project QuietHours.xcodeproj -scheme QuietHoursPreview -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" -quiet build

# CGWindowID of the window owned by a given PID.
cat > "$WORK/winid.swift" <<'EOF'
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0["kCGWindowOwnerPID"] as? Int32) == pid }
let best = mine.max { (($0["kCGWindowBounds"] as? [String: Double])?["Width"] ?? 0) < (($1["kCGWindowBounds"] as? [String: Double])?["Width"] ?? 0) }
if let id = best?["kCGWindowNumber"] { print(id) }
EOF
swiftc -O -o "$WORK/winid" "$WORK/winid.swift" 2>/dev/null
mkdir -p "$OUT"
defaults -currentHost write "$DOMAIN" hourCycle h12
defaults -currentHost write "$DOMAIN" showSeconds -bool NO
defaults -currentHost write "$DOMAIN" pureBlack -bool YES
defaults -currentHost write "$DOMAIN" dim -float 0

launch() {   # style, finish, time, extra args...
  local style=$1 finish=$2 time=$3; shift 3
  defaults -currentHost write "$DOMAIN" style "$style"
  defaults -currentHost write "$DOMAIN" "finish.$style" "$finish"
  "$BIN" -QHBare 1440x900 -QHTime "$time" "$@" >/dev/null 2>&1 & PID=$!
}
stop() { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; PID=""; sleep 1; }
window() { local w=""; for _ in $(seq 1 30); do w="$("$WORK/winid" "$PID")"; [[ -n "$w" ]] && break; sleep 0.3; done; echo "$w"; }

for shot in "${SHOTS[@]}"; do
  read -r name still gif settle <<<"$shot"
  if [[ $# -gt 0 ]] && [[ ! " $* " == *" $name "* ]]; then continue; fi
  style="$(echo "$name" | tr '[:upper:]' '[:lower:]')"

  for finish in dark light; do
    launch "$style" "$finish" "$still"; sleep "$settle"
    wid="$(window)"; [[ -n "$wid" ]] || { echo "no window for $name ($finish, pid $PID, alive: $(kill -0 "$PID" 2>/dev/null && echo yes || echo no))" >&2; exit 1; }
    screencapture -x -o -l "$wid" "$WORK/still.png"
    sips -s format png --resampleWidth 1200 "$WORK/still.png" --out "$OUT/$style-$finish.png" >/dev/null
    stop
  done

  # GIF: ~3.6 s burst through the minute change, dark finish.
  rm -rf "$WORK/frames"; mkdir -p "$WORK/frames"
  launch "$style" dark "$gif"; sleep 1.2
  wid="$(window)"
  for i in $(seq -w 1 36); do screencapture -x -o -l "$wid" "$WORK/frames/f$i.png"; sleep 0.02; done
  stop
  ffmpeg -loglevel error -y -framerate 10 -pattern_type glob -i "$WORK/frames/f*.png" \
    -vf "scale=600:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
    "$OUT/$style.gif"
  echo "$name: $style-dark.png $style-light.png $style.gif ($(du -h "$OUT/$style.gif" | cut -f1))"
done
