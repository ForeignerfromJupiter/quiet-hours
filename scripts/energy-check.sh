#!/usr/bin/env bash
# Energy check: each style full screen on one display for a while; reports average CPU (% of one
# core) of the process. Compositing happens in WindowServer and isn't counted here; Lumen's own
# GPU time can be logged with QH_LUMEN_GPU=1.
#
#   scripts/energy-check.sh [screen=0] [seconds-per-style=30] [Style…]
#
# Uses the Release Preview app (build it first, or run scripts/soak-test.sh).
set -euo pipefail

SCREEN=${1:-0}; SECS=${2:-30}; shift 2 2>/dev/null || shift $#
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/DerivedData/Build/Products/Release/QuietHoursPreview.app/Contents/MacOS/QuietHoursPreview"
STYLES=("$@"); (( ${#STYLES[@]} )) || STYLES=(hinge chorus breath lumen prose slice poster module ticker echo shutter specimen board)
P=""
trap '[[ -n "$P" ]] && kill "$P" 2>/dev/null' EXIT

printf "%-9s %7s\n" style "CPU %"
for s in "${STYLES[@]}"; do
  "$BIN" -QHStyle "$s" -QHFullScreen YES -QHScreen "$SCREEN" -QHTime 09:58:40 >/dev/null 2>&1 &
  P=$!
  sleep 8   # settle: full-screen transition, first layout, caches
  # top -l N -s 5: N samples 5 s apart; the first sample has no CPU delta, so drop it.
  n=$(( SECS / 5 + 1 ))
  cpu=$(top -l "$n" -s 5 -pid "$P" -stats pid,cpu | awk -v p="$P" '$1==p {c[++k]=$2}
    END {for (i=2;i<=k;i++) sc+=c[i]; printf "%.1f", sc/(k-1)}')
  printf "%-9s %7s\n" "$s" "$cpu"
  kill "$P"; P=""; sleep 2
done
