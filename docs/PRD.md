# Quiet Hours: PRD

Nov 8, 2026 · @Ashik

Quiet Hours is a free, open source macOS screensaver with thirteen clock styles: Hinge, Chorus, Breath, Lumen, Prose, Slice, Poster, Module, Ticker, Echo, Shutter, Specimen and Board. It ships as signed and notarized savers, one per style ("Quiet Hours – Hinge" and so on), in one download on GitHub, works on Macs from macOS 12 onward, and follows the system's light or dark mode.

## Goals and non-goals

**Goals**

1. Thirteen clock styles that look and move like the browser prototype (`reference/prototype.html`), or better, rendered natively at full refresh rate.
2. Every style follows macOS light or dark mode by default, with a manual override.
3. One download from GitHub Releases holding one `.saver` file per style, one per style, each installed with a double-click and shown as its own tile in System Settings → Screen Saver, with no Gatekeeper warning. *(Changed Nov 8, 2026, from a single all-in-one saver: styles are picked from the Screen Saver grid, not an Options menu.)*
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

### Prose

The time as one sentence, set large like a page of a book.

- Language: round to the nearest five minutes. One or two minutes past a mark reads "just after"; three or four reads "nearly" plus the next mark. Phrases run "o'clock", "five past", "ten past", "a quarter past", "twenty past", "twenty-five past", "half past", then "twenty-five to" down to "five to".
- Midnight and noon are named ("It's nearly midnight."). Time of day replaces AM/PM, based on the hour named: in the morning (5 to 11), in the afternoon (12 to 16), in the evening (17 to 20), at night (21 to 4).
- Approaching noon reads "to noon" (11:33 to 11:57, "It's twenty-five to noon."), mirroring midnight, so the morning is never called the afternoon. *(Decided Nov 8, 2026.)*
- Apostrophes are curly on screen ("It’s", "o’clock"); the sentence builder and this table keep straight ones.
- The hour word is italic. The sentence ends with a period.
- Type: Instrument Serif (OFL, bundled), 9.6% of screen width, line height 1.04, left aligned with a 9% inset, balanced lines, max width 80% of the screen.
- Rewrite: compare old and new sentences word by word and keep the shared start and end untouched. Changing words dissolve letter by letter (380 ms, rising 0.22 em with a slight blur, 14 ms stagger), then the new words rise in letter by letter (800 ms, 30 ms stagger).
- Caret: a thin bar after the period, blinking on a 1.2 s cycle.
- Caption: the exact time in small mono under a short rule, following the 12/24h and seconds settings.
- English only in v1. The sentence builder is one pure function so other languages can be added later.

| Time | Sentence |
| --- | --- |
| 20:00 | It's *eight* o'clock in the evening. |
| 20:06 | It's just after five past *eight* in the evening. |
| 20:08 | It's nearly ten past *eight* in the evening. |
| 20:30 | It's half past *eight* in the evening. |
| 20:58 | It's nearly *nine* o'clock at night. |
| 23:58 | It's nearly *midnight*. |
| 00:07 | It's just after five past *midnight*. |
| 12:00 | It's *noon*. |
| 12:30 | It's half past *twelve* in the afternoon. |
| 11:35 | It's twenty-five to *noon*. |

### Shared look for Slice, Poster, Module, Ticker, Echo, Shutter, Specimen and Board

These eight styles share one palette and one accent. Night: radial background from #17171b to #08080a, ink #efebe2, accent amber #f0b35e. Paper: radial background from #f3f0e9 to #ddd7cb, ink #161514, accent ink blue #2b4c7e. Numerals use Anybody at weight 800.

### Slice

Heavy numerals built from horizontal ribbons. The slicing is visible at rest, not only during the change.

- Size: numeral size is the smaller of 60% of screen height and whatever fits the time in 86% of screen width. Each digit cell is 0.72 x the numeral size, with 0.04 between digits and 0.3 for the colon. In 12h mode a leading blank digit is removed and the rest re-centres.
- Ribbons: each digit is cut into 14 horizontal ribbons with a hairline gap of 0.75% of the numeral size (at least 1 px), masked to the digit's own cell.
- Sway: at rest each ribbon drifts sideways by up to 1.1% of the numeral size on a sine wave (about 4.2 s period), phase-shifted per ribbon and per digit so a slow wave runs through the numerals.
- Seconds: over each minute one ribbon at a time steps out by 5% of the numeral size and turns accent, moving from the top ribbon to the bottom (about 4.3 s per ribbon) with a smooth in-and-out.
- Change: ribbons shear apart from the centre ribbon outward (34 ms delay per ribbon from the centre), in alternating directions, travelling 1.2 digit widths over 760 ms with exponential in-out easing. While moving, a ribbon slants by up to 0.4 skew in proportion to its speed, trails four fading ghost copies, and is tinted accent by its speed, cooling to ink as it lands. When several digits change, each starts 130 ms after the one to its left.
- Colon: two squares, each cut into three ribbons, blinking at full opacity for half a second and 30% for the other half.

### Poster

Hours and minutes set enormous and cropped off the page, cutting through each other and one accent disc, like a Swiss International Style poster.

- Composition: hours, minutes and the disc are drawn into one layer combined with XOR, so wherever two shapes overlap they knock out to the background.
- Type: Anybody 800, condensed, at about 104% of screen height (the stacked layout uses 88%).
- Layouts: three compositions, chosen by the hour modulo 3, so the poster re-composes every hour.

| Layout | Hours | Minutes | Disc | Captions |
| --- | --- | --- | --- | --- |
| 0 | Left-aligned at x -3.5%, baseline 79% | Right-aligned at x 103%, baseline 113% | Centre (80%, 27%), radius 13% of height | Top right |
| 1 | Right-aligned at x 103.5%, baseline 74% | Left-aligned at x -3%, baseline 114% | Centre (16%, 22%), radius 12% | Bottom right |
| 2 | Centred, baseline 60%, size 88% | Centred, baseline 113%, size 88% | Centre (88%, 52%), radius 9% | Bottom left |

- Drift: hours drift sideways by up to 0.8% of width (about 2.4 min period), minutes by 0.8% on a different period, and the disc vertically by 2% of height.
- Minute change: old minutes slide up by one screen height while new minutes rise from below, 1.1 s, exponential in-out.
- Hour change: over 1.5 s, the old hours exit left, old minutes exit down and the old disc shrinks; new hours enter from the right, new minutes rise from below, and the new disc pops in with overshoot starting a third of the way through. Captions fade across.
- Details: a faint six-column grid (ink at 5%); two letter-spaced mono caption lines in the layout's free corner (the weekday and date, then "QUIET HOURS / NO. 20" with AM/PM and optional seconds); an accent seconds bar along the bottom edge, 0.4% of height tall, filling across the minute.

### Module

Numerals built on a 3 x 5 grid of tiles from squares and quarter circles, Bauhaus style.

- Tiles: each tile is a rounded rectangle with per-corner radii. Straight tiles have no rounding; a curve tile has one corner rounded at the full tile size, which makes a quarter circle. Empty tiles have scale 0. Tiles have a gap of 5% of the tile size.
- Colour: straight tiles are ink and curve tiles are accent, with the colour blending in step with the corner radius during a morph.
- Size: tile size is the smaller of 82% of width divided by the layout's width in tiles and 60% of height divided by 5. Digits are 3 tiles wide with 0.7 tiles between them; the colon takes 2.2 tiles.
- Change: every tile tweens to its new shape over 820 ms, scale with overshoot and corner radii with exponential easing, staggered by (row + column) x 55 ms so the change runs as a diagonal wave.
- Colon: two accent discs that pulse to 85% size every half second.
- Seconds: 30 short dashes under the digits fill with accent across the minute.
- Background: a faint dot grid at 7% ink, aligned to the tile grid.
- Digit patterns (rows top to bottom; `#` square, `.` empty, `a` rounded top-left, `b` rounded top-right, `c` rounded bottom-right, `d` rounded bottom-left):

```text
0 a#b #.# #.# #.# d#c      5 ### #.. ##b ..# ##c
1 a#. .#. .#. .#. ###      6 a## #.. ##b #.# d#c
2 a#b ..# a#c #.. ###      7 ### ..# ..# ..# ..#
3 ##b ..# .## ..# ##c      8 a#b #.# ### #.# d#c
4 #.# #.# d## ..# ..#      9 a#b #.# d## ..# ##c
```

### Ticker

The time and date as one enormous line of type, scrolling endlessly like a news ticker.

- Main line: Anybody 800 condensed at 46% of screen height, centred vertically, scrolling left at 6% of screen width per second. The stream repeats time (solid ink), an accent dot (radius 8.5% of the type size), the date in outline (stroke 1.2% of type size, e.g. "SUNDAY 08 NOV"), another dot.
- New minutes: each item's text is fixed when it enters from the right, so new times arrive on the line while older ones scroll away.
- Side tickers: two letter-spaced mono lines ("QUIET HOURS / date / time AM/PM") at 11% and 92% of height, ink at 42%, scrolling the opposite way at a third of the speed, each with a hairline rule.
- Seconds: when on, the main time item includes seconds.

### Echo

Big numerals with six outline echoes stacked behind them.

- Layers: one solid ink numeral in front, six accent outlines behind (stroke 0.7% of numeral size), each offset by 2.4% of numeral size per layer and fading towards the back.
- Orbit: the offset direction rotates once a minute like a moving light source, which makes the extrusion a seconds hand.
- Change: each layer swaps 70 ms after the one in front of it; a swap slides the old digit up and out and the new one up from below over 420 ms, exponential in-out. When several digits change, each starts 110 ms after the previous.
- Size: numerals fill up to 52% of height or 80% of width, whichever is smaller.

### Shutter

The time behind a camera iris.

- Iris: seven blades. At rest the aperture is 86% of half the screen diagonal, so only the blade tips show in the corners, breathing by ±1.8% on a slow cycle and turning very slowly.
- Blades: each blade is the region between two neighbouring aperture edges extended outward. Alternate blades are 10% darker; edges get a thin dark line. Rest colour is a quiet tone (#1d1e23 at night, #d0c9bb on paper), blending to the accent as the iris closes.
- Change: close over 380 ms (cubic ease-in) while rotating about 63°, hold closed until 540 ms (the time swaps at 460 ms, hidden), then reopen over 700 ms (exponential ease-out).
- Numerals: Anybody 800, up to 46% of height or 74% of width, centred under the iris.

### Specimen

The time set twelve times as a type specimen sheet.

- Grid: 4 columns x 3 rows of ruled cells under a mono header ("QUIET HOURS / SPECIMEN / ANYBODY VARIABLE" and the date).
- Axes: columns set width 55, 84, 114, 144; rows set weight 220, 520, 820. A weight wave of ±150 ripples diagonally across the sheet (about 7 s period).
- Labels: each cell shows its live axis values in small mono ("WDTH 84 · WGHT 531").
- Seconds: one cell at a time turns accent, moving through all twelve across the minute.
- Change: cells update in reading order, 75 ms apart; each fades and rises out, then fades and rises in over 460 ms.

### Board

A Swiss timetable of world time.

- Header: local time very large (Anybody 800 at width 78), with the local city from the system time zone, the date, AM/PM and UTC offset in mono on the right.
- Seconds bar: an accent bar under the header fills across the minute.
- Rows: six cities (London, New York, San Francisco, Berlin, Tokyo, Sydney, with Dubai as a substitute if one matches the local zone), each with city name, offset from local ("−5h 30m"), day relative to local (TODAY, TOMORROW, YESTERDAY) and time.
- Working hours: a small dot before each city turns accent when it's between 09:00 and 18:00 there.
- Change: the header and then each row, 90 ms apart, scramble their digits through random numbers and settle left to right (70 ms per character).
- Time zones come from the system time zone database, so daylight saving is always correct.

## Appearance and options

Every style defaults to **Auto**: it shows its dark finish when macOS is in dark mode and its light finish in light mode, and switches live if the mode changes while the saver runs. The user can pin a finish per style instead.

| Style | Dark finish | Light finish |
| --- | --- | --- |
| Hinge | Graphite: charcoal cards, warm white numerals, near-black room | Ivory: cream cards, near-black numerals, dark warm room |
| Chorus | Night: dark faces, warm white hands | Paper: off-white faces, near-black hands |
| Breath | Graphite: warm white on graphite | Paper: near-black on warm paper |
| Lumen | Night: warm white light points, additive glow | Paper: graphite points on paper |
| Prose | Night: warm white serif on graphite | Paper: near-black serif on warm paper |
| Slice | Night: warm white ribbons, amber accent | Paper: near-black ribbons, ink blue accent |
| Poster | Night: warm white type, amber disc | Paper: near-black type, ink blue disc |
| Module | Night: warm white squares, amber curves | Paper: near-black squares, ink blue curves |
| Ticker, Echo, Shutter, Specimen, Board | Night: shared palette, amber accent | Paper: shared palette, ink blue accent |

**Options panel** (the saver's Options button in System Settings, `configureSheet`)

| Setting | Choices | Default |
| --- | --- | --- |
| Style | One saver per style; chosen in the Screen Saver grid, not in Options | — |
| Finish | Auto, or the style's dark or light finish | Auto |
| Time format | System, 12-hour, 24-hour | System (from the user's locale settings) |
| Seconds | On, off | Off |
| Pure black | On, off: the dark finish's room is #000 throughout (OLED pixels off, no mini-LED glow) | On |
| Displays | Main display only, all displays | All displays |
| Dim | 0 to 60% | 0% |

The panel shows a small live preview of the chosen style and finish. Settings are stored with `ScreenSaverDefaults` under the saver's bundle ID.

**OLED care** *(added Nov 8, 2026)*: every style except Lumen drifts by a few pixels (about 0.4% of the shorter side) on a slow 6–7 minute path, snapped to whole pixels, so static shapes never sit on the same pixels for long. Lumen's particles never hold still, so it needs none.

## Technical approach

One `ScreenSaverView` subclass hosts the style. The savers are built from the same sources; each bundle is its own Swift module (so their classes never clash when the host loads several into one process) and names its style in its Info.plist. Each style is a self-contained renderer behind one small protocol, so styles can be built and tuned one at a time.

**Stack:** Swift, ScreenSaver framework, Core Animation, Core Text, Metal. Deployment target macOS 12, universal binary (arm64 + x86\_64). Project generated with XcodeGen so it's reproducible from the repo. No third-party dependencies.

| Part | Job | Approach |
| --- | --- | --- |
| QuietHoursView | Principal class of every `.saver` (`<Module>.QuietHoursView`); runs its bundle's style, drives frames, handles start/stop | `ScreenSaverView`, frames from a display link (`NSView.displayLink` on macOS 14+, `CVDisplayLink` below) |
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

1. **Sign** each `.saver` bundle with a *Developer ID Application* certificate, hardened runtime on, secure timestamp.
2. **Package** them in one `.dmg` with a short "double-click the ones you want" note, and sign the DMG.
3. **Notarize** the DMG with `notarytool` using an App Store Connect API key, then **staple** the ticket to the DMG (and to each `.saver` too, if `stapler` accepts it) so it validates offline.
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
| Poster's XOR knockout has no direct Core Animation equivalent | Overlaps render wrong or slowly | Render the type layer with Core Graphics using the XOR blend mode (or Metal), cached per minute and only re-rendered during drift and transitions | Action: prove it in the first step of Phase 7 |
| Thirteen styles make v1.0 large | Release slips, quality varies between styles | Ship v1.0 after Phase 8 with the first eight styles; ship Ticker, Echo, Shutter, Specimen and Board as v1.1 | Action: decide the v1.0 cut before Phase 9 |

## Milestones

1. **Phase 1: Skeleton and Hinge.** XcodeGen project with the `.saver` and PreviewApp targets, ClockStyle protocol, settings, Auto appearance, Hinge in both finishes.
   - Exit: Hinge runs in PreviewApp and installed as a screensaver on this Mac; flips match the prototype; switching macOS between light and dark changes the finish.
2. **Phase 2: Breath.** Bundled variable font, weight fill, breathing, digit squeeze, tick scale.
   - Exit: smooth at 60 fps full screen on the BenQ; side-by-side with the prototype, it feels the same or better.
3. **Phase 3: Chorus.** Faces, thick hands with shadows, minute sweep, half-minute patterns.
   - Exit: every digit 0 to 9 reads clearly; patterns run at :27 to :36 and return cleanly.
4. **Phase 4: Lumen.** Particle field on Metal, scatter and re-form, trails, both finishes, then one round of pushing the design further.
   - Exit: under 10% CPU on Apple Silicon at 60 fps; Ashik signs off on the look.
5. **Phase 5: Prose.** Sentence builder with unit tests against the Prose table, bundled Instrument Serif, word-level rewrite animation, caret, caption, both finishes.
   - Exit: every row of the Prose table renders exactly; only changed words animate.
6. **Phase 6: Slice.** Ribbon rendering, sway, seconds ribbon, centre-out shear with skew, ghosts and accent tint, sliced colon.
   - Exit: every digit change matches the prototype side by side; 60 fps full screen.
7. **Phase 7: Poster.** XOR type layer, three hourly layouts, drift, minute and hour transitions, grid, captions, seconds bar.
   - Exit: all three layouts verified with a "next hour" control; overlaps knock out cleanly with no flicker.
8. **Phase 8: Module.** Tile renderer with per-corner radii, digit patterns, diagonal morph wave, accent colon, seconds dashes, dot grid.
   - Exit: digits 0 to 9 read clearly; every change morphs tile by tile with no pops.
9. **Phase 9: Ticker.** Main scrolling stream with per-item text, outline date, accent dots, counter-scrolling mono tickers.
   - Exit: scrolls smoothly with no visible seams or jumps for an hour; new minutes enter only from the right.
10. **Phase 10: Echo.** Layered numerals, orbiting extrusion, layer-by-layer swap cascade.
    - Exit: the orbit completes once a minute; changes cascade front to back exactly as in the prototype.
11. **Phase 11: Shutter.** Seven-blade iris geometry, breathing rest state, close, swap and reopen timeline, accent blend.
    - Exit: blades never show gaps at any aperture; the time swap is never visible.
12. **Phase 12: Specimen.** Ruled grid, per-cell axis settings, weight wave, live axis labels, seconds cell, cascade.
    - Exit: width and weight axes visibly change across the sheet with the bundled Anybody; 60 fps full screen.
13. **Phase 13: Board.** Header, seconds bar, city rows from the system time zone database, working-hours dots, digit scramble.
    - Exit: times, offsets and day labels are correct for every city, including across a daylight-saving change (unit-tested with fixed dates).
14. **Phase 14: Options panel and release.** `configureSheet` with live preview, GitHub Actions signing and notarization, README with GIFs, release.
    - Exit: a fresh download from GitHub installs with no Gatekeeper warning on a second Mac.

## Claude Code kickoff prompt

Before pasting:

1. Create an empty folder, e.g. `~/Dev/quiet-hours`.
2. Export this doc as Markdown and save it as `docs/PRD.md`.
3. Save the prototype file as `reference/prototype.html`.
4. Open Claude Code in that folder.

```text
You're building "Quiet Hours", an open source macOS screensaver with five clock styles. Read docs/PRD.md completely, then read reference/prototype.html. The prototype is the visual and motion spec: its timings, easing curves, sizes and colors are what the native version must match or beat.

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

Don't start Breath, Chorus, Lumen, Prose, the Options panel or the release pipeline yet. Put ideas for later phases in docs/NOTES.md.
```

For each later phase, start a fresh Claude Code session with: "Read CLAUDE.md, docs/PRD.md and reference/prototype.html. Phases 1 to N are done. Plan Phase N+1 the same way: plan first, wait for my OK, build in small steps, give me a test checklist against its exit criteria." For Lumen, also ask it to build two or three variations in PreviewApp before settling on one.

**Prose phase prompt** (use when Phases 1 to 4 are done):

```text
Read CLAUDE.md, docs/PRD.md and reference/prototype.html. Phases 1 to 4 are done. Build Phase 5: the Prose style.

- Port proseTokens from the prototype into a pure Swift function and unit-test it against every row of the Prose table in the PRD before any rendering work.
- Bundle Instrument Serif (OFL, from Google Fonts) with its license and register it like Anybody.
- Match the prototype exactly: size, inset, line height, balanced lines, italic hour word, caret, caption under a short rule.
- Rewrite animation: diff old and new sentences word by word, keep the shared start and end untouched, dissolve the changed words letter by letter, then rise the new words in, using the PRD's timings. Use one layer per glyph (Core Text glyph runs into CALayers or CATextLayers) so each letter can animate on its own.
- Night and Paper finishes, resolved by Auto appearance like the other styles.
- Must hold 60 fps full screen and stay quiet between rewrites (no redraw when nothing changes except the caret).

Plan first and wait for my OK. Build in small steps, building with xcodebuild after each. Finish with a test checklist against the Phase 5 exit criteria and a git commit.
```

**Slice phase prompt** (when Phases 1 to 5 are done):

```text
Read CLAUDE.md, docs/PRD.md and reference/prototype.html. Phases 1 to 5 are done. Build Phase 6: the Slice style.

- Match the PRD's Slice spec and the prototype's Slice exactly: sizing that fits 12h and 24h, 14 ribbons with hairline gaps, idle sway, the seconds ribbon stepping down across the minute, the centre-out shear with alternating directions, speed skew, four trailing ghosts, speed-based accent tint, 130 ms digit stagger, and the sliced blinking colon.
- Render each digit once per change into a cached image (one ink, one accent), then draw ribbons as clipped slices of those images, on Core Animation layers or Metal, whichever holds 60 fps full screen.
- Night and Paper finishes via Auto appearance, using the shared palette in the PRD.

Plan first and wait for my OK. Build in small steps with xcodebuild after each. Finish with a test checklist against the Phase 6 exit criteria and a git commit.
```

**Poster phase prompt** (when Phase 6 is done):

```text
Read CLAUDE.md, docs/PRD.md and reference/prototype.html. Phases 1 to 6 are done. Build Phase 7: the Poster style.

- First, prove the XOR knockout natively: hours, minutes and the accent disc combined so overlaps cut out to the background, rendered with Core Graphics XOR blending (or Metal). Show me that before building the rest.
- Then match the PRD's Poster spec and the prototype: the three hourly layouts from the layout table, drift, the minute slide-up, the 1.5 s hour re-composition with the disc popping in, the six-column grid, captions in each layout's free corner, and the accent seconds bar.
- Add a "Next hour" control to the PreviewApp so all three layouts can be checked quickly.
- Night and Paper finishes via Auto appearance.

Plan first and wait for my OK. Build in small steps with xcodebuild after each. Finish with a test checklist against the Phase 7 exit criteria and a git commit.
```

**Module phase prompt** (when Phase 7 is done):

```text
Read CLAUDE.md, docs/PRD.md and reference/prototype.html. Phases 1 to 7 are done. Build Phase 8: the Module style.

- Encode the digit patterns from the PRD as data and unit-test that each digit maps to the expected 15 tiles.
- Each tile is a rounded rectangle with per-corner radii and a scale. A change tweens scale (with overshoot) and radii (exponential) over 820 ms, staggered by (row + column) x 55 ms. Colour blends from ink to accent with the corner radius.
- Match the prototype: tile gap, sizing for 12h and 24h, accent colon discs pulsing, 30 seconds dashes, faint dot grid.
- Night and Paper finishes via Auto appearance.

Plan first and wait for my OK. Build in small steps with xcodebuild after each. Finish with a test checklist against the Phase 8 exit criteria and a git commit.
```

**Phases 9 to 13 prompt** (one per phase; replace N and STYLE, and add that style's focus line from the table below):

```text
Read CLAUDE.md, docs/PRD.md and reference/prototype.html. Phases 1 to N-1 are done. Build Phase N: the STYLE style.

- Match the PRD's STYLE spec and the prototype's STYLE exactly: sizes, timings, easing, palette and both finishes via Auto appearance.
- FOCUS LINE FROM THE TABLE
- Must hold 60 fps full screen and stay quiet when nothing is moving.

Plan first and wait for my OK. Build in small steps with xcodebuild after each. Finish with a test checklist against the Phase N exit criteria and a git commit.
```

| Phase | Style | Focus line to add |
| --- | --- | --- |
| 9 | Ticker | Fix each item's text when it enters from the right; measure items with Core Text and scroll with a sub-pixel offset so there are no seams. |
| 10 | Echo | Draw the six outline layers as cached glyph paths; drive each layer's swap with its own 70 ms delay so the cascade reads front to back. |
| 11 | Shutter | Build the blades from the aperture polygon's extended edges; hide the time swap entirely while the iris is closed. |
| 12 | Specimen | Use Core Text font variation attributes for the width and weight axes per cell; confirm the bundled Anybody exposes both axes before building the grid. |
| 13 | Board | Use TimeZone and Calendar for every city; unit-test offsets and day labels with fixed dates either side of a daylight-saving change. |
