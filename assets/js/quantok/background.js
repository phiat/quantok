// Populates the SVG background glyph layers once after page load.
// The SVG <animateTransform> elements handle motion natively; this module
// only stamps the text glyphs into the three layer <g> containers.

const SVG_NS = "http://www.w3.org/2000/svg";

const ALPHA = "abcdefghijklmnopqrstuvwxyz";
const HEX = "0123456789abcdef";
const BIN = "01";

// Deterministic PRNG so the field is the same on every load — the warm-accent
// budget can then truly mean "1–2% area max".
function mulberry32(seed) {
  return function () {
    let t = (seed += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function pickChar(rng) {
  const r = rng();
  if (r < 0.55) return BIN[Math.floor(rng() * BIN.length)];
  if (r < 0.85) return ALPHA[Math.floor(rng() * ALPHA.length)];
  return HEX[Math.floor(rng() * HEX.length)];
}

function populateLayer(opts) {
  const layer = document.getElementById(opts.layerId);
  if (!layer) return;
  const rng = mulberry32(opts.seed);
  const warmBudget = Math.max(1, Math.floor(opts.count * 0.015));
  let warmUsed = 0;

  const positions = [];
  for (let i = 0; i < opts.count; i++) {
    positions.push({
      x: Math.floor(rng() * 1920),
      y: Math.floor(rng() * 1080),
      ch: pickChar(rng),
      op: 0.04 + rng() * 0.04,
      size: opts.minSize + Math.floor(rng() * (opts.maxSize - opts.minSize + 1)),
      warmRoll: rng(),
    });
  }

  // Two stacked copies so the linear translate animation wraps seamlessly.
  for (let pass = 0; pass < 2; pass++) {
    const dy = pass === 0 ? 0 : 1080;
    for (const p of positions) {
      const t = document.createElementNS(SVG_NS, "text");
      t.setAttribute("x", p.x);
      t.setAttribute("y", p.y + dy);
      t.setAttribute("font-family", "ui-monospace, 'SF Mono', Menlo, Consolas, monospace");
      t.setAttribute("font-size", p.size);
      t.setAttribute("text-anchor", "middle");
      t.setAttribute("dominant-baseline", "middle");

      let fill = "#adb6c4";
      if (pass === 0) {
        if (warmUsed < warmBudget && p.warmRoll > 0.997) {
          fill = p.warmRoll > 0.9985 ? "#ffc49b" : "#ffefd3";
          p._warm = fill;
          warmUsed++;
        }
      } else if (p._warm) {
        fill = p._warm;
      }

      t.setAttribute("fill", fill);
      t.setAttribute("opacity", p.op.toFixed(3));
      t.textContent = p.ch;
      layer.appendChild(t);
    }
  }
}

export function initBackground() {
  if (!document.getElementById("q-bg-layer-deep")) return;
  populateLayer({ layerId: "q-bg-layer-deep", count: 520, seed: 1011, minSize: 3, maxSize: 5 });
  populateLayer({ layerId: "q-bg-layer-mid", count: 380, seed: 2027, minSize: 5, maxSize: 7 });
  populateLayer({ layerId: "q-bg-layer-near", count: 220, seed: 3041, minSize: 7, maxSize: 10 });
}
