# Quiet Hours

A free, open source macOS screensaver with calm clock styles. It follows your Mac's light or
dark mode and your 12/24-hour setting automatically.

**Status:** early development. Hinge (split-flap) works; Chorus, Breath and Lumen are coming.
Signed releases will be published on GitHub Releases.

## Install from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the script installs it
with Homebrew if it's missing).

```bash
scripts/install-local.sh --open
```

Then pick **Quiet Hours** in System Settings → Screen Saver. To remove it:

```bash
scripts/install-local.sh --uninstall
```

Supports macOS 12 Monterey and later on Apple Silicon and Intel.

## License

MIT (see `LICENSE`). The bundled Anybody font is © The Anybody Project Authors, under the SIL
Open Font License 1.1 (`Resources/Fonts/OFL.txt`).
