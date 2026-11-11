# Notes for later phases

Ideas and findings that don't belong to Phase 1. Not commitments.

## From Phase 1

- **System Settings thumbnails** are done: `scripts/make-thumbnails.sh` renders them from the real
  renderer (90:58, framed at 90% so the tile's edge trim never cuts the clock; Poster full-bleed).
  macOS caches tile images forever; use `install-local.sh --refresh-thumbnails` after changing them.
- **Lingering `legacyScreenSaver`.** We stop all work on `willstop`. Some savers also call
  `exit(0)` there, because the host process stays alive. Measure with Activity Monitor and
  Instruments over an hour before deciding; exiting would also kill the System Settings preview.
- **12h layout jump.** Fixed Nov 12 2026 (`Common/LeadingSlotChange`), see below.
- **Label font.** The prototype's AM/PM uses Geist Mono 500; we use SF Mono Medium. Bundling Geist
  Mono (OFL) would match exactly. Decide when Chorus and Breath need the same label.
- **Gradient banding.** The dark radial room gradient can band on 8-bit panels. Option: draw it
  once into a bitmap with ±0.5/255 noise and use that as layer contents.
- **Dim** (0–60%) and **Displays** (main only / all) are wired (Options panel, Nov 9 2026).
- **Reduce motion.** Every style honours it (checked Nov 12 2026).
- **Seconds cards** flip every second at 700 ms each. That's fine for CPU, but a "calm seconds"
  variant (no bounce) might suit them better.
- **Debug harness.** The `-QHFreeze` and `-QHFlipIn` launch arguments made motion review easy.
  Reuse them for the Chorus sweep and the Breath squeeze.

## Breath (first pass done)

- Builds four `CTFont`s with variations and four glyph paths per frame. Profile on the BenQ at
  full screen; if it stutters, cache paths at weight steps of ~5 and width steps of ~1.
- Not yet compared side by side with the prototype at 60 fps (Phase 2 exit).

## Chorus (first pass done)

- Faces are one baked bitmap; hands are 96 rotated layers. Check CPU usage at 120 Hz.
- The prototype's 8 had an open lower loop; fixed. Re-check every digit 0–9 for readability
  (Phase 3 exit).

## Lumen (GPU + push-further pass done Nov 8 2026)

- Simulation moved to a Metal compute kernel; the CPU only resamples targets once a minute.
  Full screen, Release: ~8% CPU (was ~17%), 100 fps on the 5K BenQ and 120 fps on the built-in,
  GPU ~2 ms per frame (QH_LUMEN_GPU=1 logs it).
- Trails render at ≤1.2 MP and upscale; the current points are redrawn crisp at full resolution.
- Push further: three depths (size, brightness, softness; round soft points), 12% stray particles
  wandering a slow curl flow field, and curved flights along that field during the scatter.
- Still open: try two or three variations of the stray density and flow strength side by side.
## Prose (Phase 5 done)

- Shared words reflow instantly when the line breaks change, as in the prototype. A short glide
  (≈300 ms) for the words that stay would beat it.
- English only. `ProseSentence.tokens` is the seam for other languages.
- Blur is a pre-blurred quarter-resolution bitmap per glyph that cross-fades with the vector
  glyph, not a live filter.
- Idle mode (`wantsContinuousFrames`) could also serve Hinge and Chorus between transitions.

## Refresh rates (Nov 8 2026)

- Frame drivers ask for each screen's maximum rate (`NSScreen.maximumFramesPerSecond`) and
  re-ask when the window changes screens; the thumbnail stays capped at 30.
- Steady state, full screen, Release, measured from display-link target timestamps:
  built-in 120 Hz: all styles 120 fps, 0–1 missed per 5 s; BenQ PD2706QN 100 Hz (5088×2862 px):
  Hinge/Chorus/Breath 100.0 fps with 0 missed, Lumen 99.8 fps with 1 missed per 5 s.
- **Lumen is near its budget on big panels:** 8.9 ms per frame at 5K/100 Hz (1.9 ms on the
  built-in). A 144 Hz 4K/5K panel would drop frames. Fixes, in order: render the trail texture at
  a capped pixel count (~4 MP), then move the simulation to a compute shader.
- No 144 Hz panel was available to test; the code path is the same as 100/120.

## Slice, Poster, Module (Phases 6–8, done Nov 8 2026)

- Measured full screen, Release: all three hold 100 fps on the BenQ (100 Hz, 5K) and 120 fps on
  the built-in. Slice missed 2 of 500 frames on 5K during a change; Poster rebuilds its XOR path
  every frame (drift) at ~5% CPU; Module idles between morphs (~0.5% CPU).
- Slice images are cropped to their ink and pruned after each change: footprint 107 → 71 MB on 5K
  (Hinge/Module ~35 MB). The rest is the accent copies for the seconds ribbon; 8-bit alpha masks
  tinted through a mask layer would roughly halve it again.
- Poster unions each number's outline with `CGPath.normalized` (macOS 13+). On macOS 12 the raw
  outline is used; if Anybody's overlapping contours show as holes there, union per glyph with
  a different method.
- The new PRD was merged into docs/PRD.md, keeping the eight-saver release and the Prose
  decisions it was written without.

## Pure black and burn-in shift (Nov 8 2026)

- Verified by sampling pixels: with Pure black on, every dark room is #000000; off, it is the
  original #05–#10 greys. Paper edges stay light while the clock drifts (no seam).
- The shift moved Hinge by 1 pt in 25 s in the Preview (snapped to device pixels).
- Not yet tested on a real OLED panel. If anything still burns in, the corner labels are the most
  static element; they could fade during long idle stretches.

## Release (Phase 9)

- Hardened runtime is already on for both targets. Add the Developer ID identity and
  notarization in CI; the `.p12` and API key go in repository secrets only.

## Nov 9 2026: five new styles, ultrawide, Options panel

- Ticker, Echo, Shutter, Specimen and Board were built in parallel (one agent each, isolated
  worktrees) and integrated on main; each holds full refresh rate and has unit tests.
- Ultrawide (32:9 / 21:9) checked for every style; Poster, Prose and Board now use `Room.stage`.
- Light/dark: Hinge's light finish has a light room; the view re-reads the system appearance
  every 2 s in case the sandboxed host misses the theme notification. Still to confirm on a real
  machine: switch macOS appearance while the installed saver runs.
- Windows prototype pushed as branch `windows-preview` (CI builds the .scr files; never run on
  Windows yet; eight of the thirteen styles).

## Nov 9 2026: soak test and CPU pass

`scripts/soak-test.sh` (four styles at a time in quadrant windows on one display, 6 min steady
then 2 min of stop/start every 2 s, footprint sampled every 20 s) and `scripts/energy-check.sh`
(each style full screen, average CPU). Results on an M4 Pro, 5K BenQ at 60 Hz:

| Style | Memory (MB) | Growth | After 60 restarts | CPU full screen (% of one core) |
|---|---|---|---|---|
| Hinge | 28 | none | +1 | 2.0 |
| Chorus | 29 | none | 0 | 2.4 |
| Breath | 28 | none | 0 | 7.7 |
| Lumen | 250 (GPU particle buffers) | none | 0 | 7.2 |
| Prose | 30 (was 35–38) | none | 0 (was a 70 MB spike per start, fixed) | 1.0 |
| Slice | 41 | none | −11 | 3.6 |
| Poster | 29 | none | 0 | 2.4 (was ~5) |
| Module | 28 | none | 0 | 1.2 |
| Ticker | 29 | none | −1 | 1.9 |
| Echo | 28 | none | +1 | 2.8 |
| Shutter | 28 | none | 0 | 3.1 |
| Specimen | 30 | none | 0 | 12.4 (was 24) |
| Board | 27 | none | +1 | 1.5 |

No crashes. The first run's churn phase switched windows to another style (the view re-reads the
shared Preview setting on restart); fixed with `-QHStyle` and every style re-run with it.

Prose: each start allocated ~70 MB of "owned physical footprint (graphics)" for about a second.
The cause was Core Image (blurring the soft glyph images), which sets up graphics buffers per
context even with its software renderer. Now a CPU Gaussian (Accelerate, three box passes,
unit-tested; alpha within 1/255 of Core Image on average, 13/255 at worst on blur edges): no
spike, and steady memory 37 → 30 MB. CPU excludes compositing (WindowServer).

Fixed: Specimen and Poster built a `DateFormatter` every frame (~1 ms each, ICU setup); now one
cached formatter, text rebuilt once a second. Specimen also skips Core Text shaping for its
twelve live glyph runs (Anybody doesn't kern digits or the colon: same positions, verified) and
draws its live axis labels from cached glyph outlines (`GlyphStrip`) instead of re-rasterising
twelve text layers per frame. Still the heaviest: Specimen builds twelve variable-font instances
and outlines per frame because the weight wave moves every cell (~16 µs per instance); a
per-cell outline cache would cost ~10 MB.

Not yet measured: Intel Macs, macOS 12–13, the real `legacyScreenSaver` host over hours, battery
drain directly (`powermetrics` needs sudo).

## Nov 12 2026: polish review and fixes

Reviewed all 13 in slow motion (`-QHTimeScale`) at minute and 12h hour changes, both finishes,
32:9, 1:1, seconds and 24h. Fixed:
- 12h hour change showed a wrong time ("2:59" at 1:00) in Hinge, Module, Echo; Slice snapped to
  centre. Shared `LeadingSlotChange` timeline: change then glide (going), glide then change (opening).
- Specimen overlapped at 32:9 and its widest cell hit the border: stage layout + fitted size.
- Prose: kept words glide on reflow; line-changing words cross-fade.
- Seconds labels read ":05" instead of "05 PM". Lumen strays pooled (flow field had divergence;
  now a true curl). Poster captions knock out over numerals. Board rows capped on tall screens;
  scramble digits stay plausible.
- Left as designed: Chorus's idle hour clocks in 12h (centring would split the digit across the
  pair gap), Ticker's stale item scrolling away (PRD rule).
- Preview harness: `-QHStyle` now applies last (it reset `-QHTimeScale`); `-QHScreen` keeps a
  `-QHBare` size.
