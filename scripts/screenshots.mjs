// Capture demo screenshots of Quantok via headless Chromium (Playwright).
//
// Requires: `just screenshots-setup` once (npm install + chromium download).
// Requires: dev server running at http://localhost:4000 (e.g. `just run` in another shell).
// Outputs to docs/screenshots/.

import { chromium } from "playwright";
import fs from "fs";
import path from "path";

const BASE = process.env.QUANTOK_URL || "http://localhost:4000";
const OUT_DIR = path.resolve(process.cwd(), "..", "docs", "screenshots");
fs.mkdirSync(OUT_DIR, { recursive: true });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function snap(page, name, label) {
  const out = path.join(OUT_DIR, name);
  await page.screenshot({ path: out });
  console.log(`✓ ${label} → ${path.relative(process.cwd(), out)}`);
}

async function ready(page) {
  // LiveView socket connected + canvas hook attached
  await page.waitForFunction(() => window.liveSocket?.isConnected?.());
  await page.waitForSelector("#world-canvas");
  await sleep(1500); // let Rapier WASM init + first frame render
}

async function main() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await ctx.newPage();

  console.log(`Loading ${BASE} ...`);
  await page.goto(BASE, { waitUntil: "networkidle" });
  await ready(page);

  // 1) Default sandbox at rest (just-mounted)
  await snap(page, "01-default-startup.png", "default sandbox at rest");

  // 2) Default sandbox firing: hit "fire all", wait 4s
  await page.locator('button.q-tb:has-text("fire all")').first().click();
  await sleep(4000);
  await snap(page, "02-default-firing.png", "default sandbox firing");

  // 3) Load Refinery preset, let it run 20s
  await page.locator('button.q-tb:has-text("clear")').first().click();
  await sleep(500);
  // Load buttons are styled .q-tb--load
  await page.locator('button.q-tb--load:has-text("refinery")').first().click();
  console.log("Refinery loaded — running 20s ...");
  await sleep(20_000);
  await snap(page, "03-refinery-20s.png", "refinery after 20s");

  await browser.close();
}

main().catch((err) => {
  console.error("screenshot run failed:", err);
  process.exit(1);
});
