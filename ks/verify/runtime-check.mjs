// Runs ON THE VM. Launch a bundle directly through Playwright (camoufox-js config, like ab-launch.mjs) and assert
// that privileged pages contain marker strings -- e.g. about:buildconfig, which camofox-browser's /tabs/open
// refuses (http/https only). usage: node runtime-check.mjs <bundleDir> <display> <checks.json>
// checks.json = [{"url": ..., "text": ...}] written by runtime-checks.py (validated on the host)
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
const NM = process.env.CAMOFOX_NM || '/home/crawler/camofox/node_modules';
const { launchOptions } = await import(pathToFileURL(`${NM}/@askjo/camofox-browser/node_modules/camoufox-js/dist/index.js`));
const { firefox } = await import(pathToFileURL(`${NM}/playwright-core/index.mjs`));
const [dir, display, checksFile] = process.argv.slice(2);
const checks = JSON.parse(readFileSync(checksFile, 'utf8'));
if (!/^:[0-9]+$/.test(display)) throw new Error('bad display');
const x = spawn('Xvfb', [display, '-screen', '0', '1x1x24', '-ac', '-nolisten', 'tcp'], { stdio: 'ignore', detached: true });
await new Promise(r => setTimeout(r, 1000));
let bad = 0;
try {
  const o = await launchOptions({ executable_path: '/home/crawler/.cache/camoufox/camoufox-bin', headless: false, os: 'linux',
                                  humanize: true, enable_cache: true, virtual_display: display });
  const opts = JSON.parse(JSON.stringify(o).split('/home/crawler/.cache/camoufox/camoufox-bin').join(`${dir}/camoufox-bin`)
                                         .split('/home/crawler/.cache/camoufox/fontconfig').join(`${dir}/fontconfig`));
  const b = await firefox.launch(opts);
  const p = await b.newPage();
  console.log('browser', b.version(), 'exe', opts.executablePath);
  for (const { url, text: needle } of checks) {
    await p.goto(url);
    const text = await p.textContent('body');
    const line = text.split('\n').map(s => s.trim()).filter(s => s.includes(needle)).join(' | ');
    console.log(line ? 'MARKER OK  ' : 'MARKER MISSING', url, JSON.stringify(needle), line.slice(0, 200));
    if (!line) bad++;
  }
  await b.close();
} finally { try { process.kill(-x.pid); } catch {} }
process.exit(bad ? 1 : 0);
