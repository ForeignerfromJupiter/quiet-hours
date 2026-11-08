# Notes for later phases

Ideas and findings that don't belong to Phase 1. Not commitments.

## From Phase 1

- **System Settings thumbnail.** On macOS 14+, the Screen Saver grid shows `thumbnail.png` /
  `thumbnail@2x.png` from the bundle's Resources instead of a live view. Add real per-style
  thumbnails in Phase 5. Until then the saver shows a generic tile.
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

## Release (Phase 5)

- Hardened runtime is already on for both targets. Add the Developer ID identity and
  notarization in CI; the `.p12` and API key go in repository secrets only.
