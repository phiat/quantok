/**
 * Shared constants and utility functions for the Quantok client.
 */

// Encoding -> color mapping (bright, warm palette against dark bg)
export const ENCODING_COLORS = {
  bit:      0xe0e0e0,
  byte:     0x66aaee,
  rune:     0xeea855,
  token:    0x55ddaa,
  // token_id is the numeric form of a token — gold to distinguish it visually
  // from text tokens (mint green) so the two representations don't blur.
  token_id: 0xffd166,
  ngram:    0x55dddd,
  word:     0xffc49b,  // peach glow
  phrase:   0xee9933,
  sentence: 0xd4a0ff,
};

export const DEFAULT_COLOR = 0xadb6c4;  // pale slate

export const BG_COLOR = 0x001b2e;

// Camera zoom limits
export const ZOOM_MIN = 0.25;
export const ZOOM_MAX = 4.0;
export const ZOOM_SPEED = 0.001;

// Offscreen removal threshold (pixels in physics space)
export const OFFSCREEN_THRESHOLD = 2000;

/**
 * Lerp between two hex colors by factor t (0..1).
 * Returns {r, g, b} in 0..1 range.
 */
export function lerpColor(colorA, colorB, t) {
  const ra = ((colorA >> 16) & 0xff) / 255;
  const ga = ((colorA >> 8) & 0xff) / 255;
  const ba = (colorA & 0xff) / 255;
  const rb = ((colorB >> 16) & 0xff) / 255;
  const gb = ((colorB >> 8) & 0xff) / 255;
  const bb = (colorB & 0xff) / 255;
  return {
    r: rb + (ra - rb) * t,
    g: gb + (ga - gb) * t,
    b: bb + (ba - bb) * t,
  };
}
