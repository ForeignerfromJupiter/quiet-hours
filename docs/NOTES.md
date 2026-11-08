# Notes for later phases

Ideas and findings that don't belong to Phase 1. Not commitments.

## From Phase 1

- **System Settings thumbnails** are done: `scripts/make-thumbnails.sh` renders them from the real
  renderer (90:58, framed at 90% so the tile's edge trim never cuts the clock; Poster full-bleed).
  macOS caches tile images forever; use `install-local.sh --refresh-thumbnails` after changing them.
- **Lingering `legacyScreenSaver`.** We stop all work on `willstop`. Some savers also call
  `exit(0)` there, because the host process stays alive. Measure with Activity Monitor and
  Instruments over an hour before deciding; exiting would also kill the System Settings preview.
- **12h layout jump.** At 9:59 → 10:00 (and 12:59 → 1:00) the leading card appears or disappears
  and the row re-centers instantly, as in the prototype. A 300–400 ms slide would be nicer.
- **Label font.** The prototype's AM/PM uses Geist Mono 500; we use SF Mono Medium. Bundling Geist
  Mono (OFL) would match exactly. Decide when Chorus and Breath need the same label.
- **Gradient banding.** The dark radial room gradient can band on 8-bit panels. Option: draw it
  once into a bitmap with ±0.5/255 noise and use that as layer contents.
- **Dim** (0–60%) and **Displays** (main only / all) from the Options table are not wired yet.
  Both are view-level and cheap: an overlay layer, and skipping `begin()` when
  `window.screen != NSScreen.screens.first`.
- **Reduce motion.** Hinge flips are instant when Accessibility → Reduce motion is on, as in the
  prototype. Apply the same rule to every style.
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

## Lumen (first pass done)

- A straight port, plus frame-rate-independent trail fade. The PRD's "push further" round is
  still open: particles at different depths with blur, a slow drifting field of stray
  particles, and flow-field curves instead of straight flights. Try two or three variations in
  the Preview app.
- The simulation is CPU-side (6,000 particles max, 1,500 in the thumbnail). Measured Nov 8 2026,
  Preview window 1280×800 @2x on Apple Silicon, one core: Hinge ~3%, Chorus ~4%, Breath ~8%
  (Debug), Lumen ~17% (Release), so Lumen misses the PRD's 10% target. Next: move the particle
  update to a Metal compute shader.

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
- Slice keeps one ink and one accent image per visible digit (~110 MB RSS on 5K). If memory
  matters, render 8-bit alpha masks and tint with a mask layer.
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
