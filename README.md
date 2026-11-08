# Quiet Hours

A free, open source macOS screensaver with calm clock styles. It follows your Mac's light or
dark mode and your 12/24-hour setting automatically.

**Status:** early development. All eight styles work: Hinge (split-flap), Chorus (24 clocks),
Breath (variable type), Lumen (points of light), Prose (the time as a sentence), Slice (ribboned
numerals), Poster (Swiss poster type) and Module (Bauhaus tiles).

![Hinge](Resources/Thumbnails/Hinge/thumbnail@2x.png) ![Prose](Resources/Thumbnails/Prose/thumbnail@2x.png) ![Poster](Resources/Thumbnails/Poster/thumbnail@2x.png) ![Module](Resources/Thumbnails/Module/thumbnail@2x.png)

## Download and install

1. Download **QuietHours-<version>.zip** from the [latest release](../../releases/latest) and open it.
2. Double-click the screensaver you want, for example **Quiet Hours – Hinge.saver**, and choose
   whether to install it for you or for all users.
3. Pick it in **System Settings → Screen Saver** (under "Other"). Each style is its own tile, so
   install as many as you like.

**Options…** sets the finish (Auto follows light/dark mode), 12/24-hour time, seconds and Pure
black (on by default, best for OLED screens). Works on macOS 12 Monterey and later, on Apple
Silicon and Intel. To remove one, right-click it in Screen Saver settings and choose Delete.

## Build from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the script installs it
with Homebrew if it's missing).

```bash
scripts/install-local.sh --open
```

`scripts/install-local.sh` builds and installs all eight savers, one per style. Pick **Quiet Hours – Hinge**, **– Chorus**, **– Breath**,
**– Lumen**, **– Prose**, **– Slice**, **– Poster** or **– Module** in System Settings → Screen Saver (under Other; quit and reopen System
Settings if they don't show up yet). **Options…** sets the finish (Auto follows light/dark mode),
12/24-hour time and seconds. To remove them all:

```bash
scripts/install-local.sh --uninstall
```

Supports macOS 12 Monterey and later on Apple Silicon and Intel.

## Making a release

```bash
scripts/package-release.sh   # → dist/QuietHours-<version>.zip (+ .sha256)
```

It archives a packaging-only app that carries the eight savers, has Xcode sign it with the
team's (cloud-managed) Developer ID certificate and notarize it with Apple, then lifts the
notarized savers out into the zip and checks them with Gatekeeper. Xcode must be signed into the
developer account; no passwords or keys live in the repo. Attach the zip to a GitHub Release.

## License

MIT (see `LICENSE`). Bundled fonts, both under the SIL Open Font License 1.1: Anybody © The
Anybody Project Authors (`Resources/Fonts/OFL-Anybody.txt`) and Instrument Serif © The Instrument
Serif Project Authors (`Resources/Fonts/OFL-InstrumentSerif.txt`).
