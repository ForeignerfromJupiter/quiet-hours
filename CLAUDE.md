# Quiet Hours

Open source macOS screensaver with thirteen clock styles (Hinge, Chorus, Breath, Lumen, Prose,
Slice, Poster, Module, Ticker, Echo, Shutter, Specimen, Board).
**The product is one `.saver` bundle per style:** `Quiet Hours – Hinge.saver`, `– Chorus`, … Each
is its own tile in System Settings → Screen Saver; users pick a style there, not in Options. All
build from the same sources (an XcodeGen target template). Each bundle is its own Swift module (`QuietHoursHinge`, …) so their classes never clash
when the host loads several into one process; never give a class a fixed `@objc(Name)`. The
bundle's style comes from `QHStyle` in its Info.plist (`QuietHoursView.fixedStyle`). They follow
the system's light/dark mode and 12/24h setting. `QuietHoursPreview.app` is a developer harness
only (it has a style picker) and never ships.

Specs: `docs/PRD.md` (product) and `reference/prototype.html` (visual and motion source of
truth: timings, easing curves, sizes and colors must match or beat it). Ideas for later phases:
`docs/NOTES.md`.

Status: all thirteen styles run natively; the Options panel (live preview, appearance, time
format, seconds, Pure black, displays, dim) is done; releases are Developer ID signed and
notarized (`scripts/package-release.sh`, or the tag-triggered `release.yml` once its API-key
secrets exist); CI builds and tests every push. A Windows prototype lives on the `windows-preview`
branch (untested on real Windows; see `windows/README.md` there).

Deliberate departures from the prototype (owner's calls): dark finishes use deeper blacks (rooms
go to #000) and Hinge's light finish has a light room; Hinge sizes the visible row to fill ~94% of the width (height-capped at 70%), so a
three-card 12h time is larger than a four-card one; Chorus's 8 closes its lower loop; Prose says
"to noon" from 11:33 to 11:57 and shows curly apostrophes (both recorded in the PRD).

## Build, test, install

```bash
xcodegen generate                       # project.yml → QuietHours.xcodeproj (gitignored)
xcodebuild -project QuietHours.xcodeproj -scheme QuietHours -configuration Debug -derivedDataPath build/DerivedData build
xcodebuild -project QuietHours.xcodeproj -scheme QuietHoursPreview -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
open build/DerivedData/Build/Products/Debug/QuietHoursPreview.app
xcodebuild -project QuietHours.xcodeproj -scheme Savers -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build
scripts/install-local.sh [--open | --uninstall]   # all five, Release universal → ~/Library/Screen Savers
# System Settings caches the list: quit and reopen it to see newly installed savers.
scripts/make-gallery.sh [Style…]   # README gallery: docs/images/<style>-dark/light.png + <style>.gif
scripts/make-thumbnails.sh [Style]   # re-render Resources/Thumbnails/<Style>/thumbnail(@2x).png from the real renderer
scripts/install-local.sh --refresh-thumbnails   # macOS never refreshes a cached tile image on its own
scripts/soak-test.sh [steady-min] [churn-min] [screen] [style…]   # memory over time + restart churn
scripts/energy-check.sh [screen] [seconds] [style…]   # full-screen CPU per style
```

Every step must build with zero errors and zero warnings (ignore the `appintentsmetadataprocessor`
line, which is Xcode tooling noise).

Preview debug launch arguments: `-QHTimeScale 10` (slow motion, all styles), `-QHFlipIn 2`
(next minute change lands 2 s after launch; `-QHFlipIn 30` lands on :30 for Chorus patterns),
`-QHFreeze 0.3` (Hinge only: hold every flip at 300 ms into its timeline), `-QHTime 20:07:57`
(start the clock at that time), `-QHFrameStats YES` (logs frame pacing after each burst of
animation), `-QHFullScreen YES`, `-QHScreen 1` (open on that display), `-QHBare 1240x800` (borderless,
no controls; used for thumbnails). `-QHStyle chorus` (pin this window's style), `-QHSlot 0…3` (window in that
quadrant of the screen), `-QHChurnAfter 360` (restart the view every 2 s from then on; soak tests). The window also has a "Next hour" button (Poster layouts). Serve `reference/` with the `reference` entry in
`.claude/launch.json` (http://localhost:8765) to view the prototype and ideas page live.
Pick the style for a run with `defaults -currentHost write com.ashik.quiethours.preview style chorus`.
The Preview app's settings live in `defaults -currentHost read com.ashik.quiethours.preview`.
Each installed saver keeps its own settings in the `legacyScreenSaver` container under its
bundle ID (`com.ashik.quiethours.hinge`, …), so savers and the Preview never share settings.

## Layout

```
project.yml                 XcodeGen spec: Saver template → QuietHoursHinge/Chorus/Breath/Lumen/Prose,
                            QuietHoursPreview (app), QuietHoursTests; scheme `Savers` builds all five
Sources/Shared/             compiled into both the saver and the preview app
  QuietHoursView.swift      ScreenSaverView subclass, principal class (@objc(QuietHoursView))
  Core/ClockStyle.swift     ClockStyle protocol, StyleContext, style factory
  Core/ClockTime.swift      ClockTime value type, TimeFormat (12/24h detection)
  Core/Settings.swift       Settings ↔ ScreenSaverDefaults, StyleID, FinishChoice
  Core/Appearance.swift     AppearanceResolver + SystemAppearanceObserver
  Core/FrameDriver.swift    NSView.displayLink (14+) / CVDisplayLink (12–13)
  Core/HostLifecycle.swift  com.apple.screensaver.willstop observer
  Core/Fonts.swift          bundled Anybody variable font
  Core/CubicBezier.swift    CSS cubic-bezier solver
  OptionsSheet.swift        configureSheet: style, finish, time format, seconds
  Styles/Hinge/             HingeRenderer, HingeCard, HingeFlipTimeline, HingeLayout, HingePalette
  Styles/Breath/            BreathRenderer: per-frame CTFont variations → CAShapeLayer glyphs
  Styles/Chorus/            ChorusRenderer: baked face bitmap + rotated hand layers
  Styles/Lumen/             LumenRenderer: CPU particles, Metal points + feedback-texture trails
                            (shaders compiled at runtime from a string: no Metal toolchain needed)
  Styles/Prose/             ProseSentence (pure sentence builder + word diff), ProseLayout
                            (Core Text shaping, balanced lines), ProseRenderer (one layer per glyph)
  Styles/Common/R3Look.swift  shared palette, expo/back easings, background + corner label for
                            Slice, Poster and Module
  Styles/Slice/             SliceRenderer: cached digit images (ink + accent) shown through 14
                            clipped ribbon layers each (clip → skew → old/ghosts/new/accent)
  Styles/Poster/            PosterRenderer + PosterLayout: XOR knockout as ONE even-odd CAShapeLayer
                            path (numbers unioned with CGPath.normalized), accent = same path masked to the disc
  Styles/Module/            ModuleRenderer + ModuleGlyphs (PRD patterns as data): per-corner-radius
                            CAShapeLayer tiles, dot grid via CAReplicatorLayer, idle between morphs
  Styles/Ticker/            TickerRenderer + TickerText/TickerStream: items fixed on entry, one scroll offset
  Styles/Echo/              EchoRenderer + EchoModel: 7 depth layers of cached glyph paths, orbit + cascade
  Styles/Shutter/           ShutterRenderer + ShutterGeometry/ShutterTimeline (gap-free blades, tested)
  Styles/Specimen/          SpecimenRenderer + SpecimenSheet: per-cell Anybody wdth/wght instances
  Styles/Board/             BoardRenderer + BoardModel (TimeZone/Calendar, DST-tested) 
Sources/Saver/Info.plist    NSPrincipalClass = QuietHoursView
Sources/Preview/            preview harness (window, controls)
Resources/Fonts/            Anybody-Variable.ttf, InstrumentSerif-Regular/Italic.ttf + OFL licenses (both targets)
Tests/QuietHoursTests/      unit tests, hosted by the preview app (@testable import QuietHoursPreview)
```

## Architecture

- **QuietHoursView** owns one `ClockStyle`, one `FrameDriver` and two observers (appearance,
  host lifecycle). `startAnimation` → `begin()`: re-read settings, resolve 12/24h and appearance,
  build the style under a fresh **geometry-flipped** content layer (origin top-left, like CSS),
  start frames. `stopAnimation` or `willstop` → `end()` tears everything down. It can restart.
- **ClockStyle**: `init(context:)`, `start(in:)`, `layout(bounds:scale:)`,
  `render(time:frameTime:)`, `appearanceDidChange(_:)`, `stop()`. Each call is wrapped in a
  CATransaction with actions disabled.
- **Animation is computed per frame on the CPU** from the prototype's exact curves
  (`CubicBezier`, `HingeFlipTimeline`). Don't use implicit CA animations or `CASpringAnimation`.
  This keeps the motion identical to the prototype, lets the time offset and slow motion work,
  and lets `stop` take effect immediately. Styles do no layer work between transitions.
  Exception: endless ambient loops that need no per-frame logic (Prose's caret blink) run as
  CA animations on the render server.
- **Room / OLED** (`Core/Room.swift`): with `Settings.pureBlack` (default on) a dark finish's room is
  #000 throughout; light finishes are unchanged. Every style except Lumen gets a burn-in shift: the
  view sets `contentLayer.sublayerTransform` to a slow, pixel-snapped Lissajous offset. Style
  backgrounds use `Room.frame(bounds)` (oversized by the shift margin) so the edge never shows.
  New styles: build the room with `Room.colors(...)` and `Room.frame(...)`.
- **Ultrawide screens**: compositions placed by screen-width fractions (Poster, Prose, Board) lay
  out inside `Room.stage(bounds)`, a centred area at most 16:9; backgrounds still fill the screen.
  Check new styles at 32:9 and 21:9 (Preview `-QHBare 1600x450`, `-QHBare 1720x720`).
- **Options panel** (`OptionsSheet`): live preview via `QuietHoursView.overrideSettings`; Displays
  (main only → other screens stay black and idle) and Dim (overlay above the clock) are view-level.
- **Refresh rate**: frame drivers request the screen's maximum rate (60/100/120/144…) and follow
  the window to other displays. Never assume 60 Hz: animate from `frameTime`, scale per-frame
  constants by `dt` (see Lumen's fade).
- **Idle mode**: a style returning `wantsContinuousFrames == false` gets its display link paused;
  the view renders once per second, on the second, until the style moves again (Prose uses it;
  Hinge and Chorus could).
- **Units**: styles size everything in prototype units (`u` = 1% of screen width, the CSS
  `cqw`). Hinge caps `u` so the row never takes more than 62% of the height (ultrawides).
- **Appearance**: Auto reads `AppleInterfaceStyle` via `CFPreferencesCopyAppValue` (after
  `CFPreferencesAppSynchronize`) and listens for `AppleInterfaceThemeChangedNotification`
  (re-reads after 0.5 s too). Never use `effectiveAppearance`, because the host may not update it.
- **12/24h**: `.system` → `AppleICUForce24HourTime` / `AppleICUForce12HourTime` if set, else the
  locale's `"j"` skeleton.

## Host workarounds (macOS 14+, `legacyScreenSaver`)

1. `com.apple.screensaver.willstop` → `stopAnimation()`/`end()`: display link, observers and
   layers all released. The preview app sets `followsHostLifecycle = false`.
2. `isPreview` (System Settings thumbnail) → display link capped at 30 fps.
3. Settings are re-read on every `startAnimation` (`UserDefaults.synchronize()` first).
4. No retain cycles: display links retain a proxy, not the view; every closure captures the view
   `weak`. A watchdog in `animateOneFrame` keeps the clock ticking at 30 fps if the display link
   stalls.

## Conventions

- Swift 5 mode, macOS 12 deployment target, universal binary, no third-party dependencies.
- Bundle IDs: `com.ashik.quiethours.hinge` / `.chorus` / `.breath` / `.lumen` / `.prose`, `.preview`, `.tests`. Team `HVFYWZDVQH`, automatic
  signing for local builds.
- Colors are sRGB hex taken from the prototype CSS. Put a CSS reference in a comment next to
  any ported value.
- Anything without a screen (time, formats, appearance, settings, timelines, easing) gets a unit
  test.
- New styles go in `Sources/Shared/Styles/<Name>/`, implement `ClockStyle`, get registered in
  `ClockStyles.make`, and get `isAvailable` set in `StyleID`.
- Keep the PRD, prototype and this file in sync when behavior changes.
