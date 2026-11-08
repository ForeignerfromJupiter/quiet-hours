# Quiet Hours for Windows (prototype)

This is an exploration, not a committed phase. `docs/PRD.md` still lists Windows as a non-goal.
This folder holds a working prototype of all eight styles as Windows screen savers
(`Quiet Hours - Hinge.scr` … `Quiet Hours - Module.scr`). The macOS sources are untouched.

## Recommendation: a small native `.scr` host that runs the prototype's renderers in WebView2

| | (a) WebView2 host, prototype JS | (b) Direct2D / DirectWrite port | (c) Rust + wgpu engine |
|---|---|---|---|
| **Effort** | Small. A ~1,000-line C# host, plus the eight renderers copied as they are. All eight styles run in this prototype. | Large: an eighth to a quarter of the macOS port again, per style, in C++ with COM. A third implementation to keep in sync. | Largest. You'd need text shaping, variable-font axes per frame (Breath), per-glyph layout (Prose) and particle trails (Lumen) on a GPU API that ships no text stack. It only pays off if macOS moved to the same engine, which it won't. |
| **Faithful to `reference/prototype.html`** | Exact. It *is* the prototype's code, in the same Chromium engine it was designed in. A script copies it, and CI fails if the copy is stale. | As faithful as the Mac build: matches the spec where ported, and drifts only where someone decides it should. | Same as (b). Text rendering quality depends on the crates chosen. |
| **CPU / GPU** | Highest of the three: a Chromium browser, GPU and renderer process. Canvas and CSS 3D are GPU-composited. Lumen's 6,000 particles run in JS on the CPU, like the prototype. Not measured yet. | Lowest. Per-frame CPU work as on macOS, GPU drawing. | Low, close to (b). |
| **Fonts (Anybody, Instrument Serif, OFL)** | `@font-face` from resources inside the `.scr`. Nothing is installed. The variable axes work through CSS and canvas. | `IDWriteInMemoryFontFileLoader`, plus `IDWriteFontFace5` for variable axes (Windows 10 1709+). | Embed the files and shape with e.g. `cosmic-text`/`swash`. |
| **Multi-monitor** | One borderless window per display, all sharing one WebView2 browser process. Per-monitor DPI v2. | Natural: one swap chain per display. | Natural. |
| **`.scr` protocol** (`/s`, `/p <hwnd>`, `/c`) | Handled by the native host. The page only draws. | Native. | Native, via `windows-rs`. |
| **Runtime needed** | WebView2 Evergreen runtime: built into Windows 11 and delivered to Windows 10 by Windows Update. .NET Framework 4.8 is built into Windows 10 1903+ and 11. | None. | None. |

**Choose (a).** It's the only option that gets all eight styles onto Windows for days of work
instead of months, and it matches the visual spec by construction. Its costs are higher memory
and CPU, and a dependency on the WebView2 runtime. Both are acceptable for a screen saver,
which runs while nobody is using the machine. If one style later proves too heavy, the likely
candidate is Lumen. Move its particles to WebGL in the page, or give that one style a native
renderer, before considering a rewrite. Option (b) is the fallback if the WebView2 footprint
turns out to be unacceptable.

**What this means for fidelity.** The Windows build matches the *prototype*, not the macOS
build. The owner's deliberate departures in the Mac build are not carried over:

- Hinge sizes its row to ~94% of the width.
- Chorus's 8 closes its loop.
- Prose says "to noon" and uses curly apostrophes.
- Dark rooms are deeper, apart from Pure black, which is ported.

Each departure is a small edit to `reference/prototype.html` that both platforms would then share.

## How it works

```
windows/
  src/                    C# host, .NET Framework 4.8, one project built once per style
    Program.cs            /s /p /c /w dispatch; one window per display; exit on input
    SaverForm.cs          borderless top-most window (or Settings-thumbnail child) + WebView2
    WebViewHost.cs        extracts WebView2Loader.dll, one environment, serves the page from memory
    EmbeddedAssemblies.cs loads Microsoft.Web.WebView2.Core.dll from resources (single-file .scr)
    Watchers.cs           input watcher (cursor + GetLastInputInfo); theme/time-format watcher
    OptionsForm.cs        Settings… dialog
    Settings.cs           HKCU\Software\Quiet Hours\<Style>: Finish, HourCycle, ShowSeconds, PureBlack
    SystemPrefs.cs        AppsUseLightTheme; the user's short-time format via GetLocaleInfoEx
  web/
    index.html, host.css  full-window page, @font-face, burn-in margin, Pure black
    prelude.js            the globals the renderers expect (state, parts, canvasIn…)
    styles.gen.js/.css    GENERATED: the eight renderers copied verbatim from the prototype
    main.js               mounts the style, follows host messages, frame loop, burn-in shift
  tools/extract_prototype.py   regenerates styles.gen.* from reference/prototype.html
  tools/serve.py          serves web/ like the host does, for any browser
  tests/                  xunit tests for argument parsing and 12/24h detection
  build.ps1, install.ps1
```

- **One `.scr` per style**, named like the Mac savers, with an ASCII hyphen instead of the en
  dash. The style is baked in at build time (`-p:QHStyle=Chorus` → `[AssemblyMetadata("QHStyle")]`),
  the way each macOS bundle's Info.plist sets it, so renaming the file doesn't change the style.
  Each `.scr` is a single ~1.4 MB file. The page, the three fonts, the WebView2 managed DLL and
  the native loaders for x64, x86 and arm64 are all embedded in it. On first run the loader is
  extracted to `%LOCALAPPDATA%\Quiet Hours\bin\`. The WebView2 profile lives in
  `%LOCALAPPDATA%\Quiet Hours\WebView2`.
- **No network.** The page is served from memory at `https://quiethours.example/`, and every
  other request gets a 404.
- **Light/dark**: follows `HKCU\…\Themes\Personalize\AppsUseLightTheme` (the Windows *app* mode).
  It is re-read on `WM_SETTINGCHANGE`, and again 0.6 s later, then pushed to the page, which
  remounts when the finish is Auto.
- **12/24h**: follows the user's short-time format (Settings → Time & language → Region),
  read live with `GetLocaleInfoEx(LOCALE_SSHORTTIME)`: `H` means 24-hour, `h` means 12-hour.
- **Pure black** is on by default. A dark finish's room is `#000`.
- **Burn-in shift**: every style except Lumen gets the same Lissajous drift as
  `Room.burnInOffset`, with rooms oversized by 16 px. Both ported from `Core/Room.swift`.
- **Exit on input** (`/s` only): the page reports keys, buttons, wheel, touch and mouse moves
  over 10 px. Independently, the host polls the cursor (exits beyond 12 px) and
  `GetLastInputInfo` (any input while the cursor is still), so it works whichever process has
  focus. A 0.6 s grace period after start swallows the click that launched a preview.
- **`/p <hwnd>`** (the Settings dialog thumbnail) becomes a child window of that HWND, runs at
  30 fps like the macOS `isPreview` path, and quits when the parent goes away.
- **`/c`** opens the Options dialog: finish (Auto / dark / light), time format (System / 12 / 24),
  show seconds, Pure black. With no arguments, the saver also opens this dialog. If the
  WebView2 runtime is missing, the dialog says so and links to Microsoft's installer. In `/s`
  without the runtime, the screen stays black and still exits on input.
- **`/w`** (development only) runs the saver in a normal 1280×800 window with DevTools.

## Build

Needs the .NET SDK 8+. The .NET Framework 4.8 reference assemblies come from NuGet, so Visual
Studio isn't required.

```bash
pwsh windows/build.ps1                    # → windows/dist/Quiet Hours - <Style>.scr ×8 + licences + install.ps1
```

```bash
dotnet test windows/tests                 # unit tests (any OS)
```

```bash
python3 -I windows/tools/extract_prototype.py   # after changing reference/prototype.html; commit the result
```

There's no Windows machine here, so CI does the real build:
`.github/workflows/windows.yml` runs on `windows-latest`. It checks that `web/*.gen.*` match the
prototype, runs the tests, builds all eight `.scr` files and uploads them as the
`quiet-hours-windows` artifact. It triggers on changes to `windows/**`, the prototype or the
fonts, and can also be started by hand. The project also compiles on macOS with the same SDK,
which is how it was checked here:

```bash
dotnet build windows/src -c Release -p:QHStyle=Hinge
```

Try the page in any browser (renderers, finishes, Pure black, burn-in) without Windows:

```bash
python3 -I windows/tools/serve.py   # then open:
# http://127.0.0.1:8766/index.html?style=chorus&dark=1&time=10:07:25   (pattern interlude)
# http://127.0.0.1:8766/index.html?style=hinge&dark=0&secs=1&flipIn=2  (flip 2 s after load)
# ←/→ switch style. Params: style, finish=auto|dark|light, dark, h24, secs, pure, mode=s|p|w
```

`.claude/launch.json` has this server as `windows-web`.

## Install (users)

> **About the Windows warning.** These savers aren't code-signed yet (see *Code signing* below).
> So when you open or install one, Windows may say **"Windows protected your PC … unrecognized
> app"**. Click **More info**, then **Run anyway**. Windows shows this for any program whose
> publisher it doesn't know yet; it doesn't mean the file is harmful. The source is all in this
> repository, and CI builds the files from it. On Windows 11 with **Smart App Control** on,
> unsigned programs are blocked with no override. Wait for a signed release instead of turning
> Smart App Control off.
>
> **Privacy.** Quiet Hours collects nothing. There are no analytics or accounts, and it makes no
> network requests. The page is served from inside the `.scr`, and the saver refuses any other
> request. WebView2's SmartScreen address checks are turned off. Options stay in your registry
> (`HKCU\Software\Quiet Hours`). Errors are written to a local log file that is never sent
> anywhere. The WebView2 runtime itself is a Windows component that Windows Update keeps up to
> date.

1. Download and unzip the release. If the zip came from a browser: right-click it → Properties →
   **Unblock** first, or every `.scr` inherits the download mark.
2. Move the `.scr` files somewhere permanent, e.g. `%LOCALAPPDATA%\Programs\Quiet Hours`.
3. Right-click the style you want → **Install**. Windows opens Screen Saver Settings with it
   selected. Use **Settings…** for its options and **Preview** to test.

Windows' list only shows savers in `C:\Windows\System32` plus the selected one. To see all eight
in the list, copy them there (needs admin) or use the script:

```powershell
.\install.ps1 -Style Chorus     # per user, no admin: copies all eight, selects Chorus
.\install.ps1 -AllUsers         # admin: copies all eight to System32 so all are listed
.\install.ps1 -Uninstall
```

Settings are stored per style under `HKCU\Software\Quiet Hours\<Style>`. Logs go to
`%LOCALAPPDATA%\Quiet Hours\quiethours.log`.

## Code signing and SmartScreen (open item)

The savers are unsigned. Expect friction:

- **SmartScreen** warns "Windows protected your PC" when a downloaded, unsigned `.scr` is run
  from Explorer.
- **Smart App Control** (Windows 11, when on) blocks unsigned executables with no reputation
  outright.

Signing gives the file a publisher name and lets SmartScreen reputation build up for that
identity. Since 2024, even EV certificates no longer skip that ramp, so the first releases may
still warn for a while.

Recommended: **Azure Artifact Signing** (formerly Trusted Signing).

- **Cost:** Basic is **$9.99/month**, which includes 5,000 signatures, then $0.005 each. Eight
  `.scr` files per release is far under the quota. Billing starts when the account is created.
  [Pricing](https://azure.microsoft.com/en-us/pricing/details/artifact-signing/)
- **Eligibility** (public-trust certificates): organizations in the US, Canada, EU and UK, and
  individual developers only in the US and Canada. Individual onboarding has been limited during
  the preview. This needs checking against the owner's situation before committing.
  [Quickstart](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart)
- **Fallbacks** if not eligible: SignPath Foundation (free code signing for qualifying open
  source projects), or a standard OV certificate from a CA on a hardware token or cloud HSM
  (typically a few hundred dollars a year).

Wiring it in is one CI step after `build.ps1`, before the upload, using Microsoft's signing
GitHub Action with the account endpoint, account name and certificate profile as secrets, and
`windows/dist/*.scr` as the files. Not done: there is no account yet.

## What's verified, what isn't

**Verified here (macOS):**

- `extract_prototype.py` copies the renderers. The page runs all eight styles in Chromium (the
  built-in browser pane) with no console errors: Hinge in both finishes and with seconds,
  Chorus mid-pattern, Breath, Lumen, Prose, Slice, Poster (24h + seconds) and Module (with Pure
  black off).
- Pure black makes dark rooms `#000`. The burn-in translate is applied (3 px at 1024×768). The
  canvas and DOM rooms are oversized by 16 px.
- The host builds for all eight styles with **0 warnings, 0 errors** (warnings are errors). Each
  `.exe` is 1.45 MB and carries the page, the fonts, `Microsoft.Web.WebView2.Core.dll` and the
  x64/x86/arm64 loaders as resources, plus its own `QHStyle`.
- 19 unit tests pass: argument parsing (`/s`, `/S`, `-s`, `/p 123`, `/p:123`, `/c:123`, `/c`,
  none, `/w`) and 12/24h pattern detection.

**Not verified (needs a Windows machine or the CI run):**

- That anything *runs* on Windows. This includes:
  - loading the Core DLL from memory;
  - the extracted loader and `SetLoaderDllFolderPath`;
  - serving the page via `WebResourceRequested`;
  - per-monitor DPI on mixed displays;
  - the `/p` child window inside the Settings dialog;
  - exiting on input, including the grace period;
  - live theme and time-format switching.
- The CI workflow itself, which has never run. On Windows, the WebView2 package's MSBuild
  targets may emit a warning that macOS doesn't, and warnings-as-errors would fail the build.
- That Windows shows "Quiet Hours - Hinge" (the file name) in its list, and that long names
  with spaces work in the `SCRNSAVE.EXE` registry value on every setup.
- CPU, GPU and memory cost, and behaviour over an 8-hour run (the PRD's goal 5).
- SmartScreen / Smart App Control behaviour for a screen saver started by the system rather than
  Explorer.

## Open items

1. Run the CI build and a hands-on pass on Windows 10 and 11 (x64, plus ARM64 if possible),
   covering everything in the list above.
2. Code signing: an Artifact Signing account ($9.99/month) or a fallback, then the CI step.
3. Measure resource use, Lumen especially, and decide whether its particles move to WebGL.
4. Decide whether the Mac-only departures (Hinge size, Chorus 8, Prose wording and apostrophes)
   move into the prototype so both platforms share them.
5. A release zip, and an icon (`src/QuietHours.ico` is picked up automatically if added).
6. If this becomes a real phase: update the PRD's non-goals and `CLAUDE.md`.
