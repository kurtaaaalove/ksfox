// A/B outbound probe: launch <bundleDir>/camoufox-bin with a fresh camoufox-js config + fresh profile (same as a
// camofox-browser cold start), open example.com, idle <seconds>, close. usage: node ab-launch.mjs <bundleDir> <seconds> [display]
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
const NM = process.env.CAMOFOX_NM || '/home/crawler/camofox/node_modules';
const { launchOptions } = await import(pathToFileURL(`${NM}/@askjo/camofox-browser/node_modules/camoufox-js/dist/index.js`));
const { firefox } = await import(pathToFileURL(`${NM}/playwright-core/index.mjs`));
const [dir, secs = '90', display = ':178'] = process.argv.slice(2);
const x = spawn('Xvfb', [display, '-screen', '0', '1x1x24', '-ac', '-nolisten', 'tcp'], { stdio: 'ignore', detached: true });
await new Promise(r => setTimeout(r, 1000));
const o = await launchOptions({ executable_path: '/home/crawler/.cache/camoufox/camoufox-bin', headless: false, os: 'linux',
                                humanize: true, enable_cache: true, virtual_display: display });
if (process.env.FP_EXTRA_PREFS) Object.assign(o.firefoxUserPrefs ||= {}, JSON.parse(process.env.FP_EXTRA_PREFS));
const opts = JSON.parse(JSON.stringify(o).split('/home/crawler/.cache/camoufox/camoufox-bin').join(`${dir}/camoufox-bin`)
                                       .split('/home/crawler/.cache/camoufox/fontconfig').join(`${dir}/fontconfig`));
const b = await firefox.launch(opts);
const p = await b.newPage();
await p.goto('https://example.com/');
console.log(new Date().toISOString(), 'opened', await p.title(), 'exe', opts.executablePath);
await new Promise(r => setTimeout(r, Number(secs) * 1000));
await b.close(); process.kill(-x.pid);
