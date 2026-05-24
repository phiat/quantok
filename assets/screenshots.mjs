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
  // LiveView holds a persistent websocket so "networkidle" never fires.
  await page.goto(BASE, { waitUntil: "domcontentloaded" });
  await ready(page);

  const fire = () => page.locator('button.q-tb:has-text("fire all")').first().click();
  const clear = () => page.locator('button.q-tb:has-text("clear")').first().click();
  const load = (name) => page.locator(`button.q-tb--load:has-text("${name}")`).first().click();

  // 1) Default sandbox firing — pulse fire-all a few times so the clock
  //    emitter produces several tokenes
  for (let i = 0; i < 6; i++) {
    await fire();
    await sleep(350);
  }
  await sleep(1500);
  await snap(page, "01-default-firing.png", "default sandbox firing");

  // 2) Load Toolchain preset (shell `mise list`), fire, let it run 8s
  await clear();
  await sleep(400);
  await load("toolchain");
  await sleep(600);
  await fire();
  console.log("Toolchain firing — running 8s ...");
  await sleep(8_000);
  await snap(page, "02-toolchain-8s.png", "toolchain after 8s");

  // 3) Load Refinery preset, fire, let it run 20s
  await clear();
  await sleep(400);
  await load("refinery");
  await sleep(600);
  await fire();
  console.log("Refinery firing — running 20s ...");
  await sleep(20_000);
  await snap(page, "03-refinery-20s.png", "refinery after 20s");

  // 4) Load Sha256 Decay preset — preset already enables decay@10x;
  //    fire the pangram, let it run 6s so hashes start cascading
  await clear();
  await sleep(400);
  await load("sha256_decay");
  await sleep(600);
  await fire();
  console.log("Sha256 decay firing — running 6s ...");
  await sleep(6_000);
  await snap(page, "04-sha256-decay-6s.png", "sha256 + 10x decay after 6s");

  await browser.close();
}

main().catch((err) => {
  console.error("screenshot run failed:", err);
  process.exit(1);
});
