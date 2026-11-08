/* Quiet Hours for Windows: what the prototype's style renderers expect to find around them.
 *
 * styles.gen.js is copied verbatim from reference/prototype.html and refers to these globals:
 * `reduce`, `state`, `pad`, `parts`, `ampm`, `clamp`, `canvasIn` and `offscreen`. They mirror the
 * prototype's own definitions, with two changes for a screensaver:
 *   - settings come from the host (query string, then web messages), not from localStorage;
 *   - canvasIn sizes the canvas from the canvas element itself, so the room can be oversized for
 *     the burn-in shift (see host.css), instead of from the screen element.
 * Loaded as a classic script before styles.gen.js; main.js runs after both.
 */

const QH_QUERY = new URLSearchParams(location.search);
const qhFlag = (name, fallback) => {
  const v = QH_QUERY.get(name);
  return v === null ? fallback : v === "1" || v === "true";
};

const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

/* Same shape as the prototype's state; `offset` shifts the clock (debug only). */
const state = { style: "hinge", h24: qhFlag("h24", false), secs: qhFlag("secs", false), offset: 0, v: {} };

const pad = (n) => String(n).padStart(2, "0");
function parts() {
  const d = new Date(Date.now() + state.offset);
  const h = d.getHours(), m = d.getMinutes(), s = d.getSeconds(), ms = d.getMilliseconds();
  const hd = state.h24 ? h : h % 12 || 12;
  const hs = state.h24 ? pad(hd) : hd < 10 ? " " + hd : String(hd);
  return { d, h, m, s, ms, pm: h >= 12, digits: hs + pad(m), sec: pad(s) };
}
const ampm = (p) => (state.h24 ? "" : p.pm ? "PM" : "AM");
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

function canvasIn(el) {
  const cv = document.createElement("canvas");
  cv.className = "fill";
  el.appendChild(cv);
  const o = { cv, ctx: cv.getContext("2d"), W: 0, H: 0, dpr: 1, gen: 0 };
  o.ro = new ResizeObserver(() => {
    // Layout size (not getBoundingClientRect): unaffected by the burn-in translate.
    const w = cv.offsetWidth, h = cv.offsetHeight;
    o.dpr = Math.min(2, window.devicePixelRatio || 1);
    o.W = w;
    o.H = h;
    cv.width = Math.max(1, Math.round(w * o.dpr));
    cv.height = Math.max(1, Math.round(h * o.dpr));
    o.gen++;
  });
  o.ro.observe(cv);
  return o;
}
function offscreen(w, h) {
  const c = document.createElement("canvas");
  c.width = Math.max(1, Math.ceil(w));
  c.height = Math.max(1, Math.ceil(h));
  return c;
}
