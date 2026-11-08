#!/usr/bin/env bash
# Soak test: runs every style for a while (four at a time, each in a visible quadrant window so it
# renders at full rate), samples memory footprint and CPU every 20 s, then restarts each view every
# 2 s for a while (the host starting and stopping a saver over and over) and reports growth.
#
#   scripts/soak-test.sh [steady-minutes=6] [churn-minutes=2] [screen=1] [style…]
#
# Output: build/soak/soak-<time>.csv and a summary table. The clock starts at 09:57 so every run
# crosses an hour (Poster recomposes, Board scrambles). Overwrites the Preview app's settings.
set -euo pipefail

STEADY=${1:-6}; CHURN=${2:-2}; SCREEN=${3:-1}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="$ROOT/build/DerivedData"
BIN="$DERIVED/Build/Products/Release/QuietHoursPreview.app/Contents/MacOS/QuietHoursPreview"
DOMAIN=com.ashik.quiethours.preview
STYLES=(hinge chorus breath lumen prose slice poster module ticker echo shutter specimen board)
OUT="$ROOT/build/soak"; mkdir -p "$OUT"
CSV="$OUT/soak-$(date +%Y%m%d-%H%M%S).csv"
PIDS=()
# A single style: scripts/soak-test.sh 6 2 1 hinge chorus
shift $(( $# < 3 ? $# : 3 )); (( $# )) && STYLES=("$@")
trap 'for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done' EXIT

xcodegen generate --quiet
xcodebuild -project QuietHours.xcodeproj -scheme QuietHoursPreview -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" -quiet build

defaults -currentHost write "$DOMAIN" hourCycle h12
defaults -currentHost write "$DOMAIN" showSeconds -bool YES
defaults -currentHost write "$DOMAIN" dim -float 0
echo "style,seconds,phase,footprint_mb,cpu" > "$CSV"

footprint_mb() {   # phys_footprint of a PID in MB
  footprint "$1" 2>/dev/null | awk '/phys_footprint:/ {v=$2; u=$3; if (u=="KB") v/=1024; if (u=="GB") v*=1024; printf "%.1f", v; exit}'
}

total=$(( (STEADY + CHURN) * 60 ))
for ((b = 0; b < ${#STYLES[@]}; b += 4)); do
  batch=("${STYLES[@]:b:4}")
  PIDS=()
  for i in "${!batch[@]}"; do
    s=${batch[$i]}
    defaults -currentHost write "$DOMAIN" "finish.$s" auto
    "$BIN" -QHStyle "$s" -QHBare 400x300 -QHScreen "$SCREEN" -QHSlot "$i" -QHTime 09:57:00 \
      -QHChurnAfter $((STEADY * 60)) >/dev/null 2>&1 &
    PIDS+=($!)
    sleep 1
  done
  echo "batch: ${batch[*]} ($((total / 60)) min)"
  start=$(date +%s)
  while (( $(date +%s) - start < total )); do
    t=$(( $(date +%s) - start ))
    phase=steady; (( t >= STEADY * 60 )) && phase=churn
    for i in "${!batch[@]}"; do
      p=${PIDS[$i]}
      kill -0 "$p" 2>/dev/null || { echo "${batch[$i]},$t,$phase,CRASHED,0" >> "$CSV"; continue; }
      echo "${batch[$i]},$t,$phase,$(footprint_mb "$p"),$(ps -o %cpu= -p "$p" | tr -d ' ')" >> "$CSV"
    done
    sleep 20
  done
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  PIDS=(); sleep 2
done

/usr/bin/python3 -I - "$CSV" <<'EOF'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1])))
print(f"\n{'style':9} {'warm MB':>8} {'steady end':>10} {'slope MB/h':>10} {'after churn':>11} {'churn Δ':>8} {'CPU %':>6}  verdict")
for s in dict.fromkeys(r["style"] for r in rows):
    rs = [r for r in rows if r["style"] == s]
    if any(r["footprint_mb"] == "CRASHED" for r in rs):
        print(f"{s:9} CRASHED"); continue
    st = [(int(r["seconds"]), float(r["footprint_mb"])) for r in rs if r["phase"] == "steady" and int(r["seconds"]) >= 60 and r["footprint_mb"]]
    ch = [float(r["footprint_mb"]) for r in rs if r["phase"] == "churn" and r["footprint_mb"]]
    cpu = [float(r["cpu"]) for r in rs if r["phase"] == "steady" and int(r["seconds"]) >= 60]
    n = len(st); mx = sum(t for t, _ in st) / n; my = sum(m for _, m in st) / n
    slope = sum((t - mx) * (m - my) for t, m in st) / max(1e-9, sum((t - mx) ** 2 for t, _ in st)) * 3600
    churn = (ch[-1] - st[-1][1]) if ch else 0.0
    verdict = "OK" if slope < 10 and churn < 15 else "CHECK"
    print(f"{s:9} {st[0][1]:8.1f} {st[-1][1]:10.1f} {slope:10.1f} {ch[-1] if ch else 0:11.1f} {churn:8.1f} {sum(cpu)/len(cpu):6.1f}  {verdict}")
print(f"\nraw samples: {sys.argv[1]}")
EOF
