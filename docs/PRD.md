# Quiet Hours: PRD

Nov 8, 2026 · @Ashik

Quiet Hours is a free, open source macOS screensaver with four clock styles: Hinge, Chorus, Breath and Lumen. It ships as one signed and notarized .saver on GitHub, works on Macs from macOS 12 onward, and follows the system's light or dark mode.

## Goals and non-goals

**Goals**

1. Four clock styles that look and move like the browser prototype (`reference/prototype.html`), or better, rendered natively at full refresh rate.
2. Every style follows macOS light or dark mode by default, with a manual override.
3. One `.saver` file anyone can download from GitHub Releases and install with a double-click, with no Gatekeeper warning.
4. Runs on Apple Silicon and Intel Macs, macOS 12 Monterey and later.
5. Quiet on resources: under 10% of one CPU core on an M-series Mac at 60 fps, no memory growth over an 8-hour run.
6. Clean open source repo: MIT license, README with GIFs, one-command build.

**Non-goals**

- Mac App Store distribution or any paid tier.
- Weather, calendar, photos or any network access. The saver never touches the network.
- iOS or Windows versions.
- Copying Fliqlo's name, artwork or exact look. Flip clocks are a generic form; this design is original.

## The four styles

The prototype is the source of truth for look and timing; numbers below are taken from it. Sizes are fractions of screen width so they scale to any display.

### Hinge

A split-flap clock. Four cards (HH MM), no colon; in 12h mode a leading zero hides its card entirely.

- Size: each card 21.5% of screen width, 31% tall; 1% gap inside a pair, 3.2% between hours and minutes. With seconds on, main cards shrink to 17.4% x 25% and two small seconds cards sit bottom-right.
- Card: top and bottom halves with a dark seam between, side pins at the hinge line, a 1 px highlight on the top edge, and a soft drop shadow under the bottom half.
- Flip: the top leaf (old digit) folds down to 90° in 250 ms, ease-in, while a shade grows on the card below. Then the bottom leaf (new digit) swings from 90° to 0° in 420 ms with an overshoot of about 10% so it lands with a bounce.
- Type: a condensed grotesk, heavy weight (prototype uses Anybody at width 74, weight 680), numerals at 80% of card height.
- AM/PM: small mono label above the first card.

### Chorus

A grid of 24 small analog clocks (8 columns x 3 rows, two columns per digit) whose hands spell the time.

- Faces: subtle radial gradient, 12 tick marks, thin rim. Hands are thick (11.5% of cell size), round-capped, with a soft offset shadow.
- Unused cells park both hands at 225° at 25% opacity.
- Minute change: every hand travels to its new angle with one extra full turn. Hand A turns clockwise, hand B counterclockwise. 2.6 s ease-in-out, staggered 90 ms per column and 55 ms per row so it sweeps left to right.
- Half-minute interlude: from second 27 to 36, hands leave the digits and form a pattern (rotating each minute between diagonals, horizontal lines and a starburst toward the center), rippling out from the center. Then they return to the time.
- AM/PM and optional seconds: small mono label, bottom-right.

### Breath

One large set of numerals whose weight is the clock.

- Weight fill: weight rises from 110 to 900 across each minute, so the numerals are thin at :00 and heavy at :59. On the minute it eases back down over about 1 s.
- Breathing: on top of the fill, each digit breathes in a slow 5.6 s sine cycle (weight ±80, width ±5), slightly out of phase from left to right.
- Digit change: the changing digit squeezes to width 50 and fades out in 230 ms, swaps, then springs out to width 92 with overshoot over 900 ms.
- Colon: two round dots, not a glyph. Dot size grows with the weight; opacity pulses once per second.
- Scale: 60 fine ticks below the time, every fifth one taller, filling as seconds pass.
- Type: a variable font with wide weight and width axes (prototype uses Anybody, OFL licensed, bundled in the .saver).

### Lumen

The time drawn in a few thousand points of light. This is the least settled style: build it last and push past the prototype.

- Particles: about one per 170 px² of screen (around 6,000 on a 4K display), each spring-pulled to a point sampled from the time rendered in a heavy font.
- At rest: gentle noise keeps every particle shimmering in place; brightness twinkles per particle.
- Minute change: particles get a random outward impulse, the spring loosens for 750 ms so they drift like a murmuration, then they flow into the new time.
- Dark: warm white points with additive blending and short motion trails. Light: graphite points on paper.
- Push further in the native build: depth (particles at different sizes and blur for parallax), a slow drifting field of stray particles around the digits, and particles that curve along a flow field instead of flying straight.

## Appearance and options

Every style defaults to **Auto**: it shows its dark finish when macOS is in dark mode and its light finish in light mode, and switches live if the mode changes while the saver runs. The user can pin a finish per style instead.

| Style | Dark finish | Light finish |
| --- | --- | --- |
| Hinge | Graphite: charcoal cards, warm white numerals, near-black room | Ivory: cream cards, near-black numerals, dark warm room |
| Chorus | Night: dark faces, warm white hands | Paper: off-white faces, near-black hands |
| Breath | Graphite: warm white on graphite | Paper: near-black on warm paper |
| Lumen | Night: warm white light points, additive glow | Paper: graphite points on paper |

**Options panel** (the saver's Options button in System Settings, `configureSheet`)

| Setting | Choices | Default |
| --- | --- | --- |
| Style | Hinge, Chorus, Breath, Lumen | Hinge |
| Finish | Auto, or the style's dark or light finish | Auto |
| Time format | System, 12-hour, 24-hour | System (from the user's locale settings) |
| Seconds | On, off | Off |
| Displays | Main display only, all displays | All displays |
| Dim | 0 to 60% | 0% |

The panel shows a small live preview of the chosen style and finish. Settings are stored with `ScreenSaverDefaults` under the saver's bundle ID.

## Technical approach

One `ScreenSaverView` subclass hosts whichever style is selected. Each style is a self-contained renderer behind one small protocol, so styles can be built and tuned one at a time.

**Stack:** Swift, ScreenSaver framework, Core Animation, Core Text, Metal. Deployment target macOS 12, universal binary (arm64 + x86\_64). Project generated with XcodeGen so it's reproducible from the repo. No third-party dependencies.

| Part | Job | Approach |
| --- | --- | --- |
| QuietHoursView | The `.saver` principal class; picks the style, drives frames, handles start/stop | `ScreenSaverView`, frames from a display link (`NSView.displayLink` on macOS 14+, `CVDisplayLink` below) |
| ClockStyle protocol | `start`, `render(time, frameTime)`, `stop`, `appearanceDidChange` | One renderer per style |
| HingeRenderer | Flip cards | Core Animation layers with `CATransform3D` rotations; spring timing for the bounce |
| ChorusRenderer | 24 clock faces and 48 hands | Metal (or Core Graphics if it holds 60 fps); faces pre-rendered to a texture once |
| BreathRenderer | Variable-weight numerals | Core Text with font variation attributes, redrawn per frame |
| LumenRenderer | Thousands of particles with trails | Metal: particles in a buffer, positions updated on the GPU or CPU, trails via a feedback texture |
| Settings | Read and write options | `ScreenSaverDefaults`; reloaded on every `startAnimation` |
| Appearance | Decide dark or light for Auto | Read `AppleInterfaceStyle` from the global defaults domain and observe the `AppleInterfaceThemeChangedNotification` distributed notification; don't rely on the view's `effectiveAppearance`, which the screensaver host may not update |
| TimeSource | Current time, 12/24h from locale | `DateFormatter.dateFormat(fromTemplate: "j", ...)` to detect 12-hour locales |
| Fonts | Bundled Anybody (SIL Open Font License) | Registered at load with `CTFontManagerRegisterFontsForURL`, process scope |
| PreviewApp | A plain macOS app that hosts QuietHoursView in a resizable window with a style switcher and a "skip to next minute" button | Second target sharing the same sources; this is where day-to-day iteration happens |

**Screensaver host workarounds** (needed since macOS 14, where third-party savers run inside `legacyScreenSaver`):

1. The host often keeps old instances alive after the saver stops. Observe the `com.apple.screensaver.willstop` distributed notification, stop the display link and release GPU resources there, not only in `stopAnimation`.
2. One instance runs per display plus one for the System Settings thumbnail. Check `isPreview` and keep the thumbnail cheap (lower frame rate, fewer particles).
3. Settings changes may not reach a running instance. Re-read defaults on every start.
4. Watch memory over long runs. No timers or closures that retain the view; verify with Instruments over at least one hour.

Verify each workaround on the current macOS before relying on it; the host's behavior has changed between releases.

## Distribution

Releases go out on GitHub, signed with Ashik's Developer ID and notarized by Apple, so a downloaded copy opens with no warning on any supported Mac.

1. **Sign** the `.saver` with a *Developer ID Application* certificate, hardened runtime on, secure timestamp.
2. **Package** it in a `.dmg` with a short "double-click to install" note, and sign the DMG.
3. **Notarize** the DMG with `notarytool` using an App Store Connect API key, then **staple** the ticket to the DMG (and to the `.saver` too, if `stapler` accepts it) so it validates offline.
4. **Publish** the DMG and a checksum to a GitHub Release.
5. **Automate** steps 1 to 4 in a GitHub Actions workflow that runs on a version tag. The certificate (.p12), its password and the API key live in repository secrets, never in the repo.

**Compatibility**

| macOS | Notes |
| --- | --- |
| 12 Monterey, 13 Ventura | Supported. Classic screensaver host, `CVDisplayLink` for frames |
| 14 Sonoma and later (incl. 27) | Supported. Runs in `legacyScreenSaver`; host workarounds apply |
| Intel and Apple Silicon | Both, from one universal binary |

**Repo:** MIT license, README with a GIF per style, install and uninstall steps, the font's OFL license, and the prototype in `reference/`. A Homebrew cask can come later.

## Risks

| Risk | Impact | Response | Flag |
| --- | --- | --- | --- |
| Screensaver host bugs (lingering instances, stale settings, leaks) | Battery drain, saver keeps running after wake | Workarounds in Technical approach; one-hour Instruments run before each release | Action: test on macOS 27 before v1.0 |
| Auto appearance not detected inside the host | Wrong finish shown | Read the global defaults key and observe the distributed notification, not `effectiveAppearance` | Action: verify in Phase 1 |
| Lumen and Chorus too heavy on Intel Macs | Dropped frames, fan noise | Scale particle count to GPU; cap thumbnail at 30 fps | Awareness |
| Variable-font rendering cost in Breath | Stutter when redrawing every frame | Cache glyph paths per weight step if needed | Awareness |
| Signing secrets in CI | Leaked certificate | Repository secrets only, temporary keychain in the workflow | Action: set up secrets in Phase 5 |
| Lumen direction still open | Weakest style at launch | Built last, treated as an exploration; can ship in v1.1 if not ready | Awareness |

## Milestones

1. **Phase 1: Skeleton and Hinge.** XcodeGen project with the `.saver` and PreviewApp targets, ClockStyle protocol, settings, Auto appearance, Hinge in both finishes.
   - Exit: Hinge runs in PreviewApp and installed as a screensaver on this Mac; flips match the prototype; switching macOS between light and dark changes the finish.
2. **Phase 2: Breath.** Bundled variable font, weight fill, breathing, digit squeeze, tick scale.
   - Exit: smooth at 60 fps full screen on the BenQ; side-by-side with the prototype, it feels the same or better.
3. **Phase 3: Chorus.** Faces, thick hands with shadows, minute sweep, half-minute patterns.
   - Exit: every digit 0 to 9 reads clearly; patterns run at :27 to :36 and return cleanly.
4. **Phase 4: Lumen.** Particle field on Metal, scatter and re-form, trails, both finishes, then one round of pushing the design further.
   - Exit: under 10% CPU on Apple Silicon at 60 fps; Ashik signs off on the look.
5. **Phase 5: Options panel and release.** `configureSheet` with live preview, GitHub Actions signing and notarization, README with GIFs, v1.0 release.
   - Exit: a fresh download from GitHub installs with no Gatekeeper warning on a second Mac.

## Claude Code kickoff prompt

Before pasting:

1. Create an empty folder, e.g. `~/Dev/quiet-hours`.
2. Export this doc as Markdown and save it as `docs/PRD.md`.
3. Save the prototype file as `reference/prototype.html`.
4. Open Claude Code in that folder.

```text
You're building "Quiet Hours", an open source macOS screensaver with four clock styles. Read docs/PRD.md completely, then read reference/prototype.html. The prototype is the visual and motion spec: its timings, easing curves, sizes and colors are what the native version must match or beat.

Scope for this session: Phase 1 only (skeleton + Hinge). Stop after Phase 1 and wait for my review.

Setup
- Swift, ScreenSaver framework, Core Animation. Deployment target macOS 12, universal binary (arm64 + x86_64). My Mac runs macOS 27.2 on Apple Silicon.
- Generate the project with XcodeGen (project.yml in the repo). Install XcodeGen with Homebrew if missing.
- Two targets sharing the same sources:
  1. QuietHours.saver (principal class QuietHoursView, a ScreenSaverView subclass)
  2. QuietHoursPreview, a small macOS app that hosts the same view in a resizable window, with a style picker, a light/dark toggle and a "Next minute" button that offsets the clock. We iterate here, not in System Settings.
- Bundle ID prefix: com.ashik.quiethours. Automatic signing with my Apple Developer team for local builds.
- No third-party dependencies. MIT LICENSE file. Create a CLAUDE.md capturing architecture, conventions, and build/install commands.

Phase 1 work
- ClockStyle protocol as described in the PRD's Technical approach. Settings via ScreenSaverDefaults, re-read on every startAnimation.
- Appearance: Auto resolves to dark or light by reading AppleInterfaceStyle from the global defaults domain and observing the AppleInterfaceThemeChangedNotification distributed notification. Don't rely on effectiveAppearance.
- Frame driving: NSView.displayLink on macOS 14+, CVDisplayLink below.
- Host workarounds 1 to 4 from the PRD, including stopping everything on com.apple.screensaver.willstop.
- HingeRenderer with Graphite and Ivory finishes, matching the prototype: card sizes, seam, side pins, highlight, shadow, 250 ms fold with shade, 420 ms landing with bounce, 12h hidden leading card, AM/PM label, optional seconds cards. Bundle the Anybody variable font (OFL, from Google Fonts) and register it with CTFontManagerRegisterFontsForURL.
- 12/24h follows the user's locale by default.

Working style
1. First give me a short plan: folder layout, the ClockStyle protocol, how frames are driven, and anything in the PRD you think is wrong or risky. Wait for my OK.
2. Build in small steps. After each step, build with xcodebuild and fix all errors and warnings.
3. Unit-test what doesn't need a screen: time formatting, 12/24h detection, appearance resolution.
4. Add a script, scripts/install-local.sh, that builds the .saver and copies it to ~/Library/Screen Savers so I can try it for real.
5. When Phase 1 is done, give me a manual test checklist against the Phase 1 exit criteria, and commit to git with a clear message.

Don't start Breath, Chorus, Lumen, the Options panel or the release pipeline yet. Put ideas for later phases in docs/NOTES.md.
```

For each later phase, start a fresh Claude Code session with: "Read CLAUDE.md, docs/PRD.md and reference/prototype.html. Phases 1 to N are done. Plan Phase N+1 the same way: plan first, wait for my OK, build in small steps, give me a test checklist against its exit criteria." For Lumen, also ask it to build two or three variations in PreviewApp before settling on one.
