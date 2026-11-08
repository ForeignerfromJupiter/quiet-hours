# Quiet Hours

A free, open source macOS screensaver with calm clock styles. It follows your Mac's light or
dark mode and your 12/24-hour setting automatically.

**Status:** early development. All eight styles work: Hinge (split-flap), Chorus (24 clocks),
Breath (variable type), Lumen (points of light), Prose (the time as a sentence), Slice (ribboned
numerals), Poster (Swiss poster type) and Module (Bauhaus tiles).
Signed releases will be published on GitHub Releases.

## Install from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the script installs it
with Homebrew if it's missing).

```bash
scripts/install-local.sh --open
```

This installs eight savers, one per style. Pick **Quiet Hours – Hinge**, **– Chorus**, **– Breath**,
**– Lumen**, **– Prose**, **– Slice**, **– Poster** or **– Module** in System Settings → Screen Saver (under Other; quit and reopen System
Settings if they don't show up yet). **Options…** sets the finish (Auto follows light/dark mode),
12/24-hour time and seconds. To remove them all:

```bash
scripts/install-local.sh --uninstall
```

Supports macOS 12 Monterey and later on Apple Silicon and Intel.

## License

MIT (see `LICENSE`). Bundled fonts, both under the SIL Open Font License 1.1: Anybody © The
Anybody Project Authors (`Resources/Fonts/OFL-Anybody.txt`) and Instrument Serif © The Instrument
Serif Project Authors (`Resources/Fonts/OFL-InstrumentSerif.txt`).
