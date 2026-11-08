# Quiet Hours

Open source macOS screensaver with four clock styles (Hinge, Chorus, Breath, Lumen).
**The product is a single `QuietHours.saver` bundle.** Users download it, double-click it, and
pick it in System Settings → Screen Saver. It follows the system's light/dark mode and 12/24h
setting. `QuietHoursPreview.app` is a developer harness only and never ships.

Specs: `docs/PRD.md` (product) and `reference/prototype.html` (visual and motion source of
truth: timings, easing curves, sizes and colors must match or beat it). Ideas for later phases:
`docs/NOTES.md`.

Status: Phase 1 (skeleton + Hinge) done. Breath, Chorus, Lumen, the Options panel and the
release pipeline are not started.

## Build, test, install

```bash
xcodegen generate                       # project.yml → QuietHours.xcodeproj (gitignored)
xcodebuild -project QuietHours.xcodeproj -scheme QuietHours -configuration Debug -derivedDataPath build/DerivedData build
xcodebuild -project QuietHours.xcodeproj -scheme QuietHoursPreview -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
open build/DerivedData/Build/Products/Debug/QuietHoursPreview.app
scripts/install-local.sh [--open | --uninstall]   # Release universal .saver → ~/Library/Screen Savers
```

Every step must build with zero errors and zero warnings (ignore the `appintentsmetadataprocessor`
line, which is Xcode tooling noise).

Preview debug launch arguments: `-QHTimeScale 10` (slow motion), `-QHFlipIn 2` (next minute
change lands 2 s after launch), `-QHFreeze 0.3` (hold every flip at 300 ms into its timeline).
The Preview app's settings live in `defaults -currentHost read com.ashik.quiethours.preview`.
The installed saver's settings live in the `legacyScreenSaver` container under the
`com.ashik.quiethours.saver` module, so the two never share settings.

## Layout

```
project.yml                 XcodeGen spec: QuietHours (.saver), QuietHoursPreview (app), QuietHoursTests
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
  Styles/Hinge/             HingeRenderer, HingeCard, HingeFlipTimeline, HingePalette
Sources/Saver/Info.plist    NSPrincipalClass = QuietHoursView
Sources/Preview/            preview harness (window, controls)
Resources/Fonts/            Anybody-Variable.ttf + OFL.txt (bundled into both targets)
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
- Bundle IDs: `com.ashik.quiethours.saver`, `.preview`, `.tests`. Team `HVFYWZDVQH`, automatic
  signing for local builds.
- Colors are sRGB hex taken from the prototype CSS. Put a CSS reference in a comment next to
  any ported value.
- Anything without a screen (time, formats, appearance, settings, timelines, easing) gets a unit
  test.
- New styles go in `Sources/Shared/Styles/<Name>/`, implement `ClockStyle`, get registered in
  `ClockStyles.make`, and get `isAvailable` set in `StyleID`.
- Keep the PRD, prototype and this file in sync when behavior changes.
