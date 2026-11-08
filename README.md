# Quiet Hours

A free, open source macOS screensaver with calm clock styles. It follows your Mac's light or
dark mode and your 12/24-hour setting automatically.

Thirteen styles, each its own screensaver you pick in System Settings. Signed and notarized, so
they install without warnings; macOS 12 or later, Apple Silicon and Intel, any refresh rate
(ProMotion, 144 Hz) and any shape of screen, including ultrawides.

## The styles

Every style follows your Mac's light or dark mode as it changes. Left: dark, on the minute change. Right: light.

<table>
<tr>
<td width="50%"><img src="docs/images/hinge.gif" alt="Hinge, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/hinge-light.png" alt="Hinge, light"></td>
</tr>
<tr><td colspan="2"><b>Hinge</b>: A split-flap clock: the top leaf falls and shades the card below, the bottom leaf lands with a small bounce.</td></tr>
<tr>
<td width="50%"><img src="docs/images/chorus.gif" alt="Chorus, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/chorus-light.png" alt="Chorus, light"></td>
</tr>
<tr><td colspan="2"><b>Chorus</b>: Twenty-four small clocks whose hands spell the time, sweeping in a wave each minute.</td></tr>
<tr>
<td width="50%"><img src="docs/images/breath.gif" alt="Breath, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/breath-light.png" alt="Breath, light"></td>
</tr>
<tr><td colspan="2"><b>Breath</b>: Variable-weight numerals that fill heavier across the minute and breathe slowly.</td></tr>
<tr>
<td width="50%"><img src="docs/images/lumen.gif" alt="Lumen, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/lumen-light.png" alt="Lumen, light"></td>
</tr>
<tr><td colspan="2"><b>Lumen</b>: The time in thousands of points of light that scatter and flow into the new time.</td></tr>
<tr>
<td width="50%"><img src="docs/images/prose.gif" alt="Prose, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/prose-light.png" alt="Prose, light"></td>
</tr>
<tr><td colspan="2"><b>Prose</b>: The time as a sentence, set like a page; only the words that change rewrite themselves.</td></tr>
<tr>
<td width="50%"><img src="docs/images/slice.gif" alt="Slice, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/slice-light.png" alt="Slice, light"></td>
</tr>
<tr><td colspan="2"><b>Slice</b>: Numerals cut into fourteen ribbons that sway, step out with the seconds and shear apart on a change.</td></tr>
<tr>
<td width="50%"><img src="docs/images/poster.gif" alt="Poster, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/poster-light.png" alt="Poster, light"></td>
</tr>
<tr><td colspan="2"><b>Poster</b>: Enormous cropped numbers and an accent disc that knock each other out, recomposed every hour.</td></tr>
<tr>
<td width="50%"><img src="docs/images/module.gif" alt="Module, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/module-light.png" alt="Module, light"></td>
</tr>
<tr><td colspan="2"><b>Module</b>: Bauhaus numerals from squares and quarter circles, morphing tile by tile in a diagonal wave.</td></tr>
<tr>
<td width="50%"><img src="docs/images/ticker.gif" alt="Ticker, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/ticker-light.png" alt="Ticker, light"></td>
</tr>
<tr><td colspan="2"><b>Ticker</b>: The time and date as one enormous line of type, scrolling like a news ticker.</td></tr>
<tr>
<td width="50%"><img src="docs/images/echo.gif" alt="Echo, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/echo-light.png" alt="Echo, light"></td>
</tr>
<tr><td colspan="2"><b>Echo</b>: A solid numeral with six outline echoes orbiting like a moving light; changes cascade front to back.</td></tr>
<tr>
<td width="50%"><img src="docs/images/shutter.gif" alt="Shutter, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/shutter-light.png" alt="Shutter, light"></td>
</tr>
<tr><td colspan="2"><b>Shutter</b>: The time behind a camera iris that closes, swaps the time out of sight and reopens.</td></tr>
<tr>
<td width="50%"><img src="docs/images/specimen.gif" alt="Specimen, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/specimen-light.png" alt="Specimen, light"></td>
</tr>
<tr><td colspan="2"><b>Specimen</b>: The time set twelve times across the font's width and weight axes, like a type specimen.</td></tr>
<tr>
<td width="50%"><img src="docs/images/board.gif" alt="Board, dark, changing on the minute"></td>
<td width="50%"><img src="docs/images/board-light.png" alt="Board, light"></td>
</tr>
<tr><td colspan="2"><b>Board</b>: A Swiss timetable of world time, with working-hours dots and scrambling digits.</td></tr>
</table>

## Download and install

1. Download **QuietHours-<version>.zip** from the [latest release](../../releases/latest) and open it.
2. Double-click the screensaver you want, for example **Quiet Hours – Hinge.saver**, and choose
   whether to install it for you or for all users.
3. Pick it in **System Settings → Screen Saver** (under "Other"). Each style is its own tile, so
   install as many as you like.

**Options…** shows a live preview and sets the appearance (*Match system* by default, following
light and dark mode as it changes, or always dark / always light), 12/24-hour time, seconds,
Pure black (on by default, best for OLED screens; the clock also drifts a few pixels over time
to protect them), which displays to use, and dimming. To remove a saver, right-click it in
Screen Saver settings and choose Delete.

## Windows (preview, help wanted)

An early Windows version of eight of the styles lives on the
[`windows-preview`](../../tree/windows-preview) branch. Every push builds the `.scr` files on
GitHub's Windows machines and attaches them to the run ([Actions → Windows savers](../../actions)).
It has not been tried on a real Windows PC yet and isn't signed, so Windows shows a SmartScreen
warning. If you're on Windows, try it and open an issue with what you see. Instructions are in
`windows/README.md` on that branch.

## Build from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the script installs it
with Homebrew if it's missing).

```bash
scripts/install-local.sh --open
```

`scripts/install-local.sh` builds and installs every saver, one per style; pick them in System
Settings → Screen Saver (under Other; quit and reopen System Settings if they don't show up yet).
`scripts/make-gallery.sh` re-renders the images above from the real renderer. To remove them all:

```bash
scripts/install-local.sh --uninstall
```

Supports macOS 12 Monterey and later on Apple Silicon and Intel.

## Making a release

```bash
scripts/package-release.sh   # → dist/QuietHours-<version>.zip (+ .sha256)
```

It archives a packaging-only app that carries the savers, has Xcode sign it with the
team's (cloud-managed) Developer ID certificate and notarize it with Apple, then lifts the
notarized savers out into the zip and checks them with Gatekeeper. Xcode must be signed into the
developer account; no passwords or keys live in the repo. Attach the zip to a GitHub Release.

## License

MIT (see `LICENSE`). Bundled fonts, both under the SIL Open Font License 1.1: Anybody © The
Anybody Project Authors (`Resources/Fonts/OFL-Anybody.txt`) and Instrument Serif © The Instrument
Serif Project Authors (`Resources/Fonts/OFL-InstrumentSerif.txt`).
