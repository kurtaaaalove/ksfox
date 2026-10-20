// macOS variant of ks/verify/fp-compare.mjs: ONE camoufox-js launch config (generated against the official
// bundle in the camoufox-js cache), then launch the official and the self-built Camoufox.app with that identical
// config (same CAMOU_CONFIG_* env, prefs, args), alternating official/self x2. Only executablePath is swapped
// (macOS has no bundled fontconfig; uBO stays the cache's copy for both).
// usage: node fp-compare-mac.mjs <outdir> <selfAppDir (…/Camoufox.app)> <fixtureUrl>
import { pathToFileURL } from 'node:url';
import { writeFileSync, mkdirSync } from 'node:fs';
const NM = process.env.KSFOX_NM || `${process.env.HOME}/ksfox/node_modules`;
const { launchOptions } = await import(pathToFileURL(`${NM}/camoufox-js/dist/index.js`));
const { firefox } = await import(pathToFileURL(`${NM}/playwright-core/index.mjs`));
const [outdir, selfApp, fixture] = process.argv.slice(2);
mkdirSync(outdir, { recursive: true });
// same call shape as ksfox src/browser.js on the Mac (headless, os=macos, humanize, cache, geoip off)
const base = await launchOptions({ headless: true, os: 'macos', humanize: true, enable_cache: true, block_images: false,
  geoip: false, env: { ...process.env }, i_know_what_im_doing: true });
if (process.env.FP_EXTRA_PREFS) Object.assign(base.firefoxUserPrefs ||= {}, JSON.parse(process.env.FP_EXTRA_PREFS));
const offExe = base.executablePath;
const selfExe = `${selfApp}/Contents/MacOS/camoufox`;
const baseJson = JSON.stringify(base);
writeFileSync(`${outdir}/launch-options.json`, JSON.stringify({ ...base, env: Object.keys(base.env || {}) }, null, 1));
const cfg = Object.keys(base.env || {}).filter(k => k.startsWith('CAMOU_CONFIG')).sort().map(k => base.env[k]).join('');
writeFileSync(`${outdir}/camou-config.json`, cfg);
async function runOnce(label, exe) {
  const opts = JSON.parse(baseJson); opts.executablePath = exe;
  const t0 = Date.now();
  const browser = await firefox.launch(opts);
  const page = await browser.newPage();
  const res = {};
  await page.goto(fixture, { waitUntil: 'load' });
  await page.waitForFunction(() => /^[{E]/.test(document.getElementById('out').textContent), null, { timeout: 30000 });
  res.fp = JSON.parse(await page.textContent('#out'));
  await page.click('#btn'); res.clicked = await page.textContent('#clicked');
  await page.goto('https://example.com/', { waitUntil: 'load' });
  res.example = { title: await page.title(), url: page.url(), body: (await page.evaluate(() => document.body ? document.body.innerText : '')).slice(0, 80) };
  res.version = browser.version(); res.exe = exe; res.ms = Date.now() - t0;
  await browser.close();
  writeFileSync(`${outdir}/${label}.json`, JSON.stringify(res, null, 1));
  console.log(label, res.version, res.example.title, res.clicked, res.ms + 'ms');
}
for (const [label, exe] of [['official-1', offExe], ['self-1', selfExe], ['official-2', offExe], ['self-2', selfExe]]) await runOnce(label, exe);
