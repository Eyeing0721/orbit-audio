import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { mkdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = path.join(root, '.qa');
await mkdir(output, { recursive: true });
const port = Number(process.env.PORT || 0);
let origin = process.env.ORBIT_QA_URL;
const server = process.env.ORBIT_QA_URL ? null : spawn(process.execPath, ['scripts/serve.mjs'], { cwd: root, env: { ...process.env, PORT: String(port) }, stdio: ['ignore', 'pipe', 'pipe'] });
let browser;
try {
  if (server) {
    origin = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Owned preview server did not start')), 10000);
      server.stdout.on('data', data => {
        const match = data.toString().match(/ORBIT preview: (http:\/\/127\.0\.0\.1:\d+)/);
        if (match) { clearTimeout(timer); resolve(match[1]); }
      });
      server.on('error', error => { clearTimeout(timer); reject(error); });
      server.on('exit', code => { if (code) { clearTimeout(timer); reject(new Error('Preview process exited ' + code)); } });
    });
  }
  let ready = false;
  for (let i = 0; i < 40; i++) {
    try { if ((await fetch(origin)).ok) { ready = true; break; } } catch {}
    await new Promise(resolve => setTimeout(resolve, 150));
  }
  assert(ready, 'Preview did not start');
  browser = await chromium.launch({ headless: true, ...(process.env.ORBIT_QA_BROWSER ? { executablePath: process.env.ORBIT_QA_BROWSER } : {}) });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  await page.goto(origin, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  assert.match(await page.title(), /ORBIT/);
  assert.equal(await page.locator('h1').count(), 1);
  assert.equal((await fetch(origin + '/not-a-page')).status, 404);
  assert.equal(await page.locator('.node-wires path').count(), 4);
  for (const key of ['nodes', 'curves', 'spectrum', 'spatial']) {
    await page.locator('[data-preview="' + key + '"]').click();
    const image = page.locator('#workspace-preview');
    await image.evaluate(element => element.decode());
    assert.equal(await image.evaluate(element => element.naturalWidth > 0), true);
    assert.equal(await page.locator('[role=tab][aria-selected=true]').count(), 1);
  }
  await page.locator('#tab-spatial').focus();
  await page.keyboard.press('ArrowRight');
  assert.equal(await page.locator('#tab-nodes').getAttribute('aria-selected'), 'true');
  await page.locator('#tab-spatial').click();
  const voice = page.locator('#source-voice');
  const before = await voice.getAttribute('transform');
  await page.locator('#arrival-button').click();
  assert.notEqual(await voice.getAttribute('transform'), before);
  await page.locator('#reset-scene').click();
  assert.equal(await voice.getAttribute('transform'), before);
  await voice.focus();
  await page.keyboard.press('ArrowRight');
  assert.notEqual(await voice.getAttribute('transform'), before);
  await page.locator('#reset-scene').click();
  await voice.scrollIntoViewIfNeeded();
  const bounds = await voice.boundingBox();
  await page.mouse.move(bounds.x + bounds.width / 4, bounds.y + bounds.height / 2);
  await page.mouse.down();
  await page.mouse.move(bounds.x + bounds.width / 4 + 25, bounds.y + bounds.height / 2 + 30, { steps: 4 });
  await page.mouse.up();
  assert.notEqual(await voice.getAttribute('transform'), before, 'Source drag failed');
  await page.locator('#reset-scene').click();
  await page.evaluate(() => {
    window.__clipboardText = '';
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async text => { window.__clipboardText = text; } } });
  });
  await page.locator('#copy-commands').click();
  const commands = await page.evaluate(() => window.__clipboardText);
  assert.match(commands, /powershell -NoProfile -ExecutionPolicy Bypass -File \.\\scripts\\setup_engine\.ps1 -Python python/);
  assert(!commands.includes('\\\n'), 'Invalid PowerShell continuation');
  assert.equal(await page.locator('#toast').isVisible(), true);
  const faq = page.locator('.faq-list details').first();
  await faq.locator('summary').click();
  assert.equal(await faq.getAttribute('open'), '');
  const links = await page.locator('a[href*="ORBIT_Windows_0.7.1.zip"]').evaluateAll(elements => elements.map(element => element.href));
  assert.equal(links.length, 2);
  assert(links.every(link => link.startsWith('https://github.com/Eyeing0721/orbit-audio/releases/download/v0.7.1/')));
  const imageFailures = await page.locator('img').evaluateAll(elements => elements.filter(element => element.complete && !element.naturalWidth).map(element => element.src));
  assert.deepEqual(imageFailures, []);
  for (const width of [320, 375, 768, 1024, 1440, 1920]) {
    await page.setViewportSize({ width, height: 1000 });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
    assert.equal(overflow, false, 'Horizontal page overflow at ' + width);
  }
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto(origin, { waitUntil: 'networkidle' });
  await page.screenshot({ path: path.join(output, 'desktop.png'), fullPage: true });
  await page.screenshot({ path: path.join(output, 'desktop-fold.png') });
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto(origin, { waitUntil: 'networkidle' });
  await page.locator('.menu-toggle').click();
  assert.equal(await page.locator('#mobile-nav').isVisible(), true);
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('#mobile-nav').isVisible(), false);
  await page.locator('.menu-toggle').click();
  await page.locator('#mobile-nav a[href="#workspace"]').click();
  assert.equal(await page.locator('#mobile-nav').isVisible(), false);
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
  await page.screenshot({ path: path.join(output, 'mobile.png'), fullPage: true });
  await page.screenshot({ path: path.join(output, 'mobile-fold.png') });
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.reload({ waitUntil: 'networkidle' });
  assert.equal(await page.locator('h1').isVisible(), true);
  assert.deepEqual(errors, [], 'Browser errors');
  const file = await readFile(path.join(root, 'dist/index.html'), 'utf8');
  assert(!file.includes('__SITE_URL__'), 'Unresolved site origin');
  console.log(JSON.stringify({ status: 'passed', checks: ['desktop/mobile layouts at 6 widths', 'four screenshot tabs and keyboard controls', 'SVG drag, presets, reset and keyboard movement', 'PowerShell command copy', 'FAQ', 'mobile navigation', 'download links', 'images/fonts', 'reduced motion', 'no browser errors'], screenshots: '.qa/' }, null, 2));
} finally {
  if (browser) await browser.close();
  if (server) server.kill();
}
