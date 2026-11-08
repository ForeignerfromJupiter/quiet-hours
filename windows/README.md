# Quiet Hours for Windows (prototype)

This is an exploration, not a committed phase. `docs/PRD.md` still lists Windows as a non-goal.
This folder holds a working prototype of all eight styles as Windows screen savers
(`Quiet Hours - Hinge.scr` … `Quiet Hours - Module.scr`). The macOS sources are untouched.

## For testers

> **Untested and unsigned.** This build has never run on a real Windows PC: you are the first.
> It isn't code-signed yet, so Windows may say **"Windows protected your PC"**. Click **More info**,
> then **Run anyway**. Windows shows this for any program whose publisher it doesn't know yet; it
> doesn't mean the file is harmful, and the source is all in this repository. On Windows 11 with
> **Smart App Control** on, unsigned programs are blocked with no "Run anyway". Please report it
> rather than turning Smart App Control off.

**You need** Windows 10 (version 1903 or later) or Windows 11, on x64 or ARM64. You also need
the Microsoft Edge WebView2 Runtime. It is already on Windows 11 and on up-to-date Windows 10;
if it's missing, the saver says so and its **Settings…** dialog links to Microsoft's installer.

**Get the build.**
1. Open the repository's **Actions** tab → **Windows savers** → the latest green run.
2. Under **Artifacts**, download **quiet-hours-windows**. You need to be signed in to GitHub.
3. Before unzipping it: right-click the zip → **Properties** → tick **Unblock** → OK. Otherwise
   every file inside keeps the "downloaded from the internet" mark.

The zip holds eight `.scr` files, `install.ps1`, `READ ME FIRST.txt` and the licences.

**Install.**
1. Make a folder that will stay put, e.g. `%LOCALAPPDATA%\Programs\Quiet Hours`, and copy the
   `.scr` files into it. Windows uses the file where it is, so don't install from Downloads.
2. Right-click a style, e.g. `Quiet Hours - Hinge.scr`, → **Install**. On Windows 11 it's under
   **Show more options**. Screen Saver Settings opens with it selected.
3. **Settings…** sets its options: finish (Auto follows Windows' app mode), time format (System
   follows your region's format), seconds, and Pure black. **Preview** runs it full screen;
   move the mouse or press a key to end it.

Windows' list only shows savers in `C:\Windows\System32`, plus the selected one. To have all eight
in the list, use the script:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Style Chorus   # just you, no admin: all eight, Chorus selected
powershell -ExecutionPolicy Bypass -File .\install.ps1 -AllUsers       # admin PowerShell: all eight listed
```

**Uninstall.** Screen Saver Settings → **Screen saver: (None)** → OK, then delete the `.scr`
files. Or:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

It removes the files and selects (None) if a Quiet Hours saver was current. It also deletes the
settings (`HKCU\Software\Quiet Hours`) and the logs and cache (`%LOCALAPPDATA%\Quiet Hours`).

**What to try.** The most useful reports cover:
- Each style in Preview and as the real screen saver (set **Wait** to 1 minute).
- Ending it: mouse, keyboard, touch. A light knock on the desk should *not* end it.
- More than one display, especially with different scaling (e.g. a 4K screen at 150% next to a
  1080p screen at 100%). Every display should show the clock, sharp, edge to edge.
- Turning a monitor off and on, or docking and undocking, while it runs.
- The small live preview in Screen Saver Settings, and closing that dialog: no Quiet Hours
  process should be left in Task Manager.
- Windows' app mode (Settings → Personalization → Colors) and the time format (Settings → Time &
  language → Region) set to Auto and System, including changing them while it runs.

**Report a problem** at [github.com/ForeignerfromJupiter/quiet-hours/issues](https://github.com/ForeignerfromJupiter/quiet-hours/issues).
Include:
- your Windows version (Win+R → `winver`) and whether it's x64 or ARM;
- your displays (how many, resolution, scaling);
- the style;
- what you did and what happened;
- a photo or screenshot if you can;
- the log file, `%LOCALAPPDATA%\Quiet Hours\quiethours.log`.

**Privacy.** Quiet Hours collects nothing: no analytics, no accounts, no network requests. The
page is served from inside the `.scr`, and the saver refuses every other request. WebView2's
SmartScreen address checks, background networking and component updates are switched off, and
crash dumps stay on your PC instead of being uploaded. Options stay in your registry. The log
file holds only the style, launch mode and error messages, and never leaves your computer. The
WebView2 runtime itself is a Windows component that Windows Update keeps current.

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
    Watchers.cs           input watcher (cursor, GetLastInputInfo + key state); theme/time-format; displays
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
  build.ps1, install.ps1, READ ME FIRST.txt (shipped in the zip for testers)
```

- **One `.scr` per style**, named like the Mac savers, with an ASCII hyphen instead of the en
  dash. The style is baked in at build time (`-p:QHStyle=Chorus` → `[AssemblyMetadata("QHStyle")]`),
  the way each macOS bundle's Info.plist sets it, so renaming the file doesn't change the style.
  Each `.scr` is a single ~1.4 MB file. The page, the three fonts, the WebView2 managed DLL and
  the native loaders for x64, x86 and arm64 are all embedded in it. On first run the loader is
  extracted to `%LOCALAPPDATA%\Quiet Hours\bin\`. The WebView2 profile lives in
  `%LOCALAPPDATA%\Quiet Hours\WebView2`.
- **No network.** The page is served from memory at `https://quiethours.example/`, and every
  other request gets a 404. Chromium's own background traffic is switched off
  (`--disable-background-networking --disable-component-update --disable-domain-reliability --no-pings`),
  as are SmartScreen URL checks. Crash dumps stay local (`IsCustomCrashReportingEnabled`).
- **Fonts** are the bundled OFL files, served from inside the `.scr`. Labels use the system's
  Cascadia Mono or Consolas through a `local()` alias. The page waits for the fonts (at most
  2.5 s) before its first frame, so canvas styles never cache a fallback face.
- **Light/dark**: follows `HKCU\…\Themes\Personalize\AppsUseLightTheme` (the Windows *app* mode).
  It is re-read on `WM_SETTINGCHANGE`, and again 0.6 s later, then pushed to the page, which
  remounts when the finish is Auto.
- **12/24h**: follows the user's short-time format (Settings → Time & language → Region),
  read live with `GetLocaleInfoEx(LOCALE_SSHORTTIME)`: `H` means 24-hour, `h` means 12-hour.
- **Pure black** is on by default. A dark finish's room is `#000`.
- **Burn-in shift**: every style except Lumen gets the same Lissajous drift as
  `Room.burnInOffset`, with rooms oversized by 16 px. Both ported from `Core/Room.swift`.
- **Exit on input** (`/s` only). The page reports keys, buttons, wheel, touch and mouse moves
  over 10 px. Independently, the host polls every 50 ms, so this works whichever process has
  focus. It exits when:
  - the cursor ends up more than 12 px from where it settled; or
  - `GetLastInputInfo` advanced *and* a key or mouse button is down or was pressed
    (`GetAsyncKeyState`).

  Mouse jitter advances `GetLastInputInfo` but does neither of those, so it never ends the
  saver. A 0.75 s grace period after start (host and page) swallows the click or key release
  that launched it.
- **Displays.** One borderless top-most window per display, sized in physical pixels (per-monitor
  DPI v2 in `app.manifest`). WebView2 picks each monitor's scale itself. When displays change
  (a DisplayPort monitor sleeping or waking, docking, a resolution change), the windows are
  reconciled by device name: new ones are added, moved ones are resized, gone ones are closed.
  A crashed WebView2 renderer is reloaded.
- **`/p <hwnd>`** (the Settings dialog thumbnail). The window takes the parent's DPI awareness,
  becomes a `WS_CHILD` of that HWND before it is ever shown, and follows the parent's size. It
  runs at 30 fps like the macOS `isPreview` path. When the dialog destroys the thumbnail (or a
  250 ms check finds the parent gone), it closes the WebView2 controller and the process exits.
- **`/c`** (and no arguments) opens the Options dialog, owned by the given HWND or the foreground
  window. Its options are finish (Auto / dark / light), time format (System / 12 / 24), show
  seconds and Pure black. If the WebView2 runtime is missing, the dialog says so and links to
  Microsoft's installer. The runtime is not bootstrapped: a screen saver shouldn't install
  software on its own. In `/s` without the runtime, each screen shows a short note, and the
  saver still exits on input. Any other start-up failure is logged; from `/c` it shows a
  message box.
- **`/w`** (development only) runs the saver in a normal 1280×800 window with DevTools.

## Build

Needs the .NET SDK 8+. The .NET Framework 4.8 reference assemblies come from NuGet, so Visual
Studio isn't required.

```bash
pwsh windows/build.ps1                    # → windows/dist/: the eight .scr, READ ME FIRST.txt, install.ps1, licences
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
- The host builds for all eight styles with **0 warnings, 0 errors** (warnings are errors).
  Each `.exe` is 1.45 MB, with its own version resource ("Quiet Hours - Hinge"). It carries as
  resources the page, the fonts, `Microsoft.Web.WebView2.Core.dll` and the x64/x86/arm64 loaders,
  plus its own `QHStyle`.
- `Microsoft.Web.WebView2.Core.dll` is IL-only and AnyCPU (its CLI header was checked), so
  loading it from memory is allowed.
- 26 unit tests pass. Argument parsing covers `/s`, `/S`, `-s`, `" /S "`, `/p 123`, `/P 123`,
  `/p:123`, `/p123`, `/c:123`, `/c`, `/c:0`, a negative handle, none, and `/w`. The rest test
  12/24h pattern detection.

**Not verified (needs a Windows machine or the CI run):**

- That anything *runs* on Windows. This includes:
  - loading the Core DLL from memory;
  - the extracted loader and `SetLoaderDllFolderPath`;
  - serving the page via `WebResourceRequested`;
  - per-monitor DPI on mixed displays;
  - display hot-plug;
  - the `/p` child window inside the Settings dialog, and its clean exit;
  - exiting on input and ignoring jitter;
  - live theme and time-format switching;
  - the missing-runtime messages;
  - `install.ps1`.
- The CI workflow itself, which has never run. On Windows, the WebView2 package's MSBuild
  targets may emit a warning that macOS doesn't, and warnings-as-errors would fail the build.
- That Windows shows "Quiet Hours - Hinge" (the file name) in its list, and that long names
  with spaces work in the `SCRNSAVE.EXE` registry value on every setup.
- Whether the Chromium switches fully silence WebView2's background traffic. The page's own
  requests are blocked regardless.
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
