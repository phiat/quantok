/**
 * Client-side tuning knobs for the world simulation. Everything in here
 * controls *how* the sim behaves — change a value here to retune; never copy
 * a constant inline. Wire-format / data / palette lives in utils.js.
 */

// Maximum alive tokenes at once. When exceeded, the oldest (FIFO by spawn
// order) are dropped so the physics loop stays under budget.
export const TOKENE_CAP = 500;

// Duration of the fading halo that flashes around a newly added node.
export const HIGHLIGHT_MS = 3000;

// Cull tokenes whose physics position drifts more than this many pixels from
// the origin on either axis. Cheap escape hatch for runaway bodies.
export const OFFSCREEN_THRESHOLD = 2000;

// How often the on-screen "fps · tok" readout refreshes.
export const FPS_INTERVAL_MS = 500;

// Camera zoom limits and scroll-wheel sensitivity.
export const ZOOM_MIN = 0.25;
export const ZOOM_MAX = 4.0;
export const ZOOM_SPEED = 0.001;

// Decay: a tokene shatters once its current integrity falls below this
// fraction of its starting integrity (so 0.05 = "down to 5% of where it
// started"). Keep in sync with the server's Quantok.Tokene.shattered?/1.
export const SHATTER_THRESHOLD = 0.05;

// Sensor cooldown per node type — prevents a tokene that's inside a zone
// from re-firing the same node every frame.
export const SENSOR_COOLDOWN_MS = {
  transformer: 1000,
  portal: 1500,
  collector: 500,
};

// Magnet tuning. dt approximates the physics step so the configured strength
// (px/s²) translates into a sensible per-frame impulse.
export const MAGNET_DT = 1 / 60;

// Conveyor surface drag tuning.
export const CONVEYOR_COUPLING = 0.15;     // tangent-speed coupling factor
export const CONVEYOR_CONTACT_BAND = 4;    // px above the surface still treated as resting

// Portal exit: drop the teleported tokene this far above the destination ring
// so it falls out the top rather than spawning inside (and re-triggering) the
// destination's sensor.
export const PORTAL_EXIT_CLEARANCE = 4;

// Per-encoding base half-lives in ms — mirrors Quantok.Tokene.@base_half_life.
// Sentinel 0 means "indestructible" (bit).
export const BASE_HALF_LIFE = {
  sentence: 8_000,
  phrase: 15_000,
  word: 30_000,
  token: 45_000,
  token_id: 60_000,
  ngram: 50_000,
  rune: 60_000,
  byte: 120_000,
  bit: 0,
};
