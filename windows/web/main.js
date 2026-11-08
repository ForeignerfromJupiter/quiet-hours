/* Quiet Hours for Windows: mounts one prototype style full window and drives it.
 *
 * The host (QuietHours.Windows) loads index.html with the settings in the query string:
 *   style=hinge|chorus|breath|lumen|prose|slice|poster|module
 *   finish=auto|dark|light     dark=1|0 (Windows app theme; omitted = prefers-color-scheme)
 *   h24=1|0  secs=1|0  pure=1|0 (Pure black, default on)
 *   mode=s (full screen: exit on input) | p (Settings thumbnail: 30 fps) | w (window)
 * and later posts {dark, h24} when the Windows theme or time format changes.
 * Debug, in any browser: time=20:07:57 starts the clock there; flipIn=2 lands the next minute
 * change 2 s after load; ←/→ switch style when not hosted.
 */
(function () {
  "use strict";

  const STYLES = { hinge: Hinge, chorus: Chorus, breath: Breath, lumen: Lumen, prose: Prose, slice: Slice, poster: Poster, module: Module };
  const ORDER = Object.keys(STYLES);
  const host = window.chrome && window.chrome.webview ? window.chrome.webview : null;

  const q = QH_QUERY;
  const cfg = {
    style: STYLES[q.get("style")] ? q.get("style") : "hinge",
    finish: ["auto", "dark", "light"].includes(q.get("finish")) ? q.get("finish") : "auto",
    dark: q.has("dark") ? qhFlag("dark", true) : null,
    pure: qhFlag("pure", true),
    mode: q.get("mode") || "w",
  };

  /* ---- Debug time controls (same idea as the macOS Preview's -QHTime / -QHFlipIn) ---- */
  const t0 = q.get("time");
  if (t0 && /^\d{1,2}:\d{2}(:\d{2})?$/.test(t0)) {
    const [h, m, s = 0] = t0.split(":").map(Number);
    const now = new Date(), want = new Date(now);
    want.setHours(h, m, s, 0);
    state.offset = want - now;
  }
  const flipIn = parseFloat(q.get("flipIn"));
  if (flipIn >= 0) {
    const p = parts();
    state.offset += (60 - p.s) * 1000 - p.ms - flipIn * 1000;
  }

  /* ---- Pure black: a dark finish's room is #000 (canvas palettes here, DOM styles in host.css) ---- */
  if (cfg.pure) {
    CHORUS_PAL.night.bg = "#000";
    LUMEN_PAL.night.bg = "0,0,0";
    R3_PAL.night.bg = ["#000", "#000"];
  }

  const stage = document.getElementById("stage");
  const screenEl = document.getElementById("screen");
  stage.classList.toggle("qh-pure", cfg.pure);

  const systemDark = () => (cfg.dark !== null ? cfg.dark : matchMedia("(prefers-color-scheme: dark)").matches);
  let active = null, mountedKey = "", lastShift = "";

  function mount() {
    const S = STYLES[cfg.style];
    const v = cfg.finish === "dark" ? S.dark : cfg.finish === "light" ? S.light : systemDark() ? S.dark : S.light;
    const key = cfg.style + "|" + v;
    if (key === mountedKey) return;
    if (active) active.destroy();
    screenEl.innerHTML = "";
    screenEl.removeAttribute("style");
    state.style = cfg.style;
    // Lumen is the one style without the burn-in shift (its points never rest on the same pixels).
    stage.classList.toggle("qh-shift", cfg.style !== "lumen");
    stage.style.transform = "";
    lastShift = "";
    active = S.mount(screenEl, v);
    mountedKey = key;
    document.title = "Quiet Hours - " + S.name;
  }

  /* ---- Host messages: theme or time format changed while running ---- */
  if (host) {
    host.addEventListener("message", (e) => {
      const m = e.data || {};
      if (typeof m.h24 === "boolean") state.h24 = m.h24;
      if (typeof m.secs === "boolean") state.secs = m.secs;
      if (typeof m.dark === "boolean") cfg.dark = m.dark;
      if (active) mount();
    });
  }
  try {
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => { if (cfg.dark === null && active) mount(); });
  } catch (e) { /* old engines */ }

  /* ---- Exit on input (full screen only). The host also watches the cursor and GetLastInputInfo. ---- */
  if (cfg.mode === "s") {
    const exit = () => { if (host) host.postMessage("exit"); };
    let origin = null;
    addEventListener("mousemove", (e) => {
      if (!origin) { origin = [e.screenX, e.screenY]; return; }
      if (Math.hypot(e.screenX - origin[0], e.screenY - origin[1]) > 10) exit();
    }, true);
    for (const type of ["keydown", "mousedown", "pointerdown", "wheel", "touchstart"]) addEventListener(type, exit, true);
  } else if (!host) {
    addEventListener("keydown", (e) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const i = ORDER.indexOf(cfg.style), d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (!d) return;
      cfg.style = ORDER[(i + d + ORDER.length) % ORDER.length];
      mount();
      e.preventDefault();
    });
  }
  addEventListener("contextmenu", (e) => e.preventDefault());

  /* ---- Burn-in shift (Sources/Shared/Core/Room.swift): slow Lissajous, ~0.4% of the short side,
     at least 3 px, at most margin - 2, snapped to device pixels. ---- */
  const MARGIN = 16;
  function burnIn(seconds) {
    const amp = Math.min(MARGIN - 2, Math.max(3, 0.004 * Math.min(innerWidth, innerHeight)));
    const s = Math.max(1, window.devicePixelRatio || 1);
    const x = amp * Math.sin((2 * Math.PI * seconds) / 437);
    const y = amp * Math.sin((2 * Math.PI * seconds) / 353 + 1.3);
    return [Math.round(x * s) / s, Math.round(y * s) / s];
  }

  /* ---- Frame loop. The Settings thumbnail is capped at 30 fps, like the macOS isPreview path. ---- */
  const minFrame = cfg.mode === "p" ? 1000 / 30 - 2 : 0;
  let last = -1e9;
  function loop(t) {
    requestAnimationFrame(loop);
    if (t - last < minFrame) return;
    last = t;
    if (!active) return;
    try { active.frame(parts(), t); } catch (err) { console.error(err); }
    if (stage.classList.contains("qh-shift") && !reduce) {
      const [x, y] = burnIn(Date.now() / 1000);
      const v = `translate(${x}px,${y}px)`;
      if (v !== lastShift) { stage.style.transform = v; lastShift = v; }
    }
  }

  /* Wait for the bundled fonts: Slice and Lumen rasterise glyphs once and would keep a fallback. */
  const fonts = ['800 100px "Anybody"', '100px "Instrument Serif"', 'italic 100px "Instrument Serif"', '500 20px "Geist Mono"'];
  const ready = Promise.all(fonts.map((f) => document.fonts.load(f))).catch(() => {});
  const timeout = new Promise((r) => setTimeout(r, 2500));
  Promise.race([ready, timeout]).then(() => {
    mount();
    requestAnimationFrame(loop);
    if (host) host.postMessage("ready");
  });
})();
