// Renders the mock-up with headless Chrome over the DevTools protocol, in real time, so
// requestAnimationFrame animations run (--virtual-time-budget barely advances rAF).
// node shoot.mjs <out.png> <width>x<height> [query] [waitMs] [scale] [js to run after load]
import { spawn } from 'node:child_process';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const [out, size = '1400x2300', query = '', waitMs = '2500', scale = '1', js = ''] = process.argv.slice(2);
const [w, h] = size.split('x').map(Number);
const here = dirname(fileURLToPath(import.meta.url));
const url = `file://${join(here, 'index.html')}${query ? '?' + query : ''}`;
const port = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', `--remote-debugging-port=${port}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'dd-chrome-'))}`, `--window-size=${w},${h}`, 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(150);
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page'); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r, { once: true }));
let id = 0; const pending = new Map();
ws.addEventListener('message', ev => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  if (m.method === 'Runtime.exceptionThrown') console.error('EXCEPTION', m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text);
  if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') console.error('CONSOLE', m.params.args.map(a => a.value ?? a.description).join(' '));
});
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: Number(scale), mobile: false });
await send('Page.enable');
await send('Page.navigate', { url });
await sleep(Number(waitMs));
if (js) {
  for (const step of js.split(';;')) {
    const m = step.match(/^wait:(\d+)$/);
    if (m) { await sleep(Number(m[1])); continue; }
    const r = await send('Runtime.evaluate', { expression: step, awaitPromise: false });
    if (r.result?.exceptionDetails) console.error('EVAL', r.result.exceptionDetails.exception?.description);
  }
}
const shot = await send('Page.captureScreenshot', { format: 'png' });
writeFileSync(out, Buffer.from(shot.result.data, 'base64'));
ws.close(); chrome.kill();
