# Quiet Hours

Open source macOS screensaver with five clock styles (Hinge, Chorus, Breath, Lumen, Prose).
**The product is five `.saver` bundles, one per style:** `Quiet Hours – Hinge.saver`, `– Chorus`,
`– Breath`, `– Lumen`, `– Prose`. Each is its own tile in System Settings → Screen Saver; users
pick a style there, not in Options. All five build from the same sources (an XcodeGen target
template). Each bundle is its own Swift module (`QuietHoursHinge`, …) so their classes never clash
when the host loads several into one process; never give a class a fixed `@objc(Name)`. The
bundle's style comes from `QHStyle` in its Info.plist (`QuietHoursView.fixedStyle`). They follow
the system's light/dark mode and 12/24h setting. `QuietHoursPreview.app` is a developer harness
only (it has a style picker) and never ships.

Specs: `docs/PRD.md` (product) and `reference/prototype.html` (visual and motion source of
truth: timings, easing curves, sizes and colors must match or beat it). Ideas for later phases:
`docs/NOTES.md`.

Status: Phases 1–5 done: all five styles run natively (Breath, Chorus and Lumen are first-pass
ports). A simple Options sheet (style, finish, time format, seconds) works in System Settings.
Still to do: Lumen's "push further" round, and Phase 6 (full Options panel with live preview,
displays and dim; thumbnails; signing, notarization and release).

Deliberate departures from the prototype (owner's calls): dark finishes use deeper blacks (rooms
go to #000); Hinge sizes the visible row to fill ~94% of the width (height-capped at 70%), so a
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
```

Every step must build with zero errors and zero warnings (ignore the `appintentsmetadataprocessor`
line, which is Xcode tooling noise).

Preview debug launch arguments: `-QHTimeScale 10` (slow motion, all styles), `-QHFlipIn 2`
(next minute change lands 2 s after launch; `-QHFlipIn 30` lands on :30 for Chorus patterns),
`-QHFreeze 0.3` (Hinge only: hold every flip at 300 ms into its timeline), `-QHTime 20:07:57`
(start the clock at that time), `-QHFrameStats YES` (logs frame pacing after each burst of
animation), `-QHFullScreen YES`, `-QHScreen 1` (open on that display). Serve `reference/` with the `reference` entry in
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
