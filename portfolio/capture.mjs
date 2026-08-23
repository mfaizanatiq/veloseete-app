#!/usr/bin/env node
/**
 * Captures portfolio frames from studio.html via Playwright.
 * Usage: node capture.mjs
 */
import { chromium } from 'playwright';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const ROOT = __dirname;
const OUT = path.join(ROOT, 'screenshots');
const FILE = path.join(ROOT, 'studio.html');

const PHONES = [
  '01-fuels-hero',
  '02-fuel-history',
  '03-fill-detail',
  '04-live-drive',
  '05-pending-review',
  '06-driver-insights',
  '07-garage',
  '08-notif-low-fuel',
  '09-notif-drive',
  '10-intel-fuel-brain',
  '11-intel-flow',
  '12-station-map',
];

const WIDES = [
  'w01-fuels-case',
  'w02-notif-case',
  'w03-drives-case',
];

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage();

  for (const id of PHONES) {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`file://${FILE}?frame=${id}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(400);
    const dest = path.join(OUT, `${id}.png`);
    await page.screenshot({ path: dest, type: 'png' });
    console.log('wrote', dest);
  }

  for (const id of WIDES) {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto(`file://${FILE}?wide=${id}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(500);
    const dest = path.join(OUT, `${id}.png`);
    await page.screenshot({ path: dest, type: 'png' });
    console.log('wrote', dest);
  }

  await browser.close();
  console.log(`\nDone — ${PHONES.length + WIDES.length} frames in ${OUT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
