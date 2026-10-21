import { chromium } from 'playwright-core';
import fs from 'fs';
const map = JSON.parse(fs.readFileSync('map.json'));
const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto('file://' + process.cwd() + '/page.html');
await page.addScriptTag({ path: 'sample.js' });
const out = {};
for (const [key, file] of Object.entries(map)) {
  out[key] = await page.evaluate(n => bake(n), file);
  console.log(key, out[key].start.length, out[key].stop.length);
}
fs.writeFileSync('baked.json', JSON.stringify(out));
await browser.close();
