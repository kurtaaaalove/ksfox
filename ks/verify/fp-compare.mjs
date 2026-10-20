// Strict fingerprint comparison: generate ONE camoufox-js launch config, then launch the official and the
// self-built Camoufox with that identical config (same CAMOU_CONFIG_* env, prefs, args), 2 runs each.
// usage: node fp-compare.mjs <outdir> <officialDir> <selfDir> <fixtureUrl> [display]
import { pathToFileURL } from 'node:url';
import { writeFileSync, mkdirSync } from 'node:fs';
import { spawn } from 'node:child_process';
const NM = '/home/crawler/camofox/node_modules';
const { launchOptions } = await import(pathToFileURL(`${NM}/@askjo/camofox-browser/node_modules/camoufox-js/dist/index.js`));
const { firefox } = await import(pathToFileURL(`${NM}/playwright-core/index.mjs`));
const [outdir, offDir, selfDir, fixture, display = ':177'] = process.argv.slice(2);
mkdirSync(outdir, { recursive: true });

const xvfb = spawn('Xvfb', [display, '-screen', '0', '1x1x24', '-ac', '-nolisten', 'tcp', '-extension', 'RENDER', '+extension', 'GLX',
  '-extension', 'COMPOSITE', '-extension', 'XVideo', '-extension', 'XVideo-MotionCompensation', '-extension', 'XINERAMA',
  '-fp', 'built-ins', '-nocursor', '-br'], { stdio: 'ignore', detached: true });
await new Promise(r => setTimeout(r, 1500));

// Same call shape as camofox-browser 1.10.1 launchBrowserInstance() (os=linux, humanize, enable_cache, virtual display)
const base = await launchOptions({ executable_path: `${offDir}/camoufox-bin`, headless: false, os: 'linux', humanize: true,
                                   enable_cache: true, virtual_display: display });
const baseJson = JSON.stringify(base);
writeFileSync(`${outdir}/launch-options.json`, JSON.stringify(base, null, 1));
const cfg = Object.keys(base.env || {}).filter(k => k.startsWith('CAMOU_CONFIG')).sort().map(k => base.env[k]).join('');
writeFileSync(`${outdir}/camou-config.json`, cfg);

async function runOnce(label, dir) {
  // bundle-level swap: every reference to the official bundle dir now points at the self-built bundle
  const opts = JSON.parse(baseJson.split(offDir).join(dir));
  const t0 = Date.now();
  const browser = await firefox.launch(opts);
  const page = await browser.newPage();
  const res = {};
  await page.goto(fixture, { waitUntil: 'load' });
  // Camoufox runs Playwright's evaluate in an isolated world, so read the result from the DOM, not window.__fp
  await page.waitForFunction(() => /^[{E]/.test(document.getElementById('out').textContent), null, { timeout: 30000 });
  res.fp = JSON.parse(await page.textContent('#out'));
  await page.click('#btn'); res.clicked = await page.textContent('#clicked');
  await page.goto('https://example.com/', { waitUntil: 'load' });
  res.example = { title: await page.title(), url: page.url(), body: (await page.evaluate(() => document.body ? document.body.innerText : "")).slice(0, 80) };
  res.version = browser.version(); res.ms = Date.now() - t0;
  await browser.close();
  writeFileSync(`${outdir}/${label}.json`, JSON.stringify(res, null, 1));
  console.log(label, res.version, res.example.title, res.clicked, res.ms + 'ms');
  return res;
}
try {
  for (const [label, dir] of [['official-1', offDir], ['self-1', selfDir], ['official-2', offDir], ['self-2', selfDir]]) await runOnce(label, dir);
} finally { try { process.kill(-xvfb.pid); } catch {} }
