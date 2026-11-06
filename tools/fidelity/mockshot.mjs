// node mockshot.mjs <index.html> <out.png> <query> <waitMs> [js]
// Captures the first live .screen (390x844) at device scale 3.
import { spawn } from 'node:child_process';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const [page, out, query, waitMs = '3000', js = ''] = process.argv.slice(2);
const url = `file://${page}?${query}`;
const port = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', `--remote-debugging-port=${port}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'dd-chrome-'))}`, '--window-size=1400,1400', 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let target;
for (let i = 0; i < 60 && !target; i++) { await sleep(150); try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page'); } catch {} }
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r, { once: true }));
let id = 0; const pending = new Map();
ws.addEventListener('message', ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } if (m.method === 'Runtime.exceptionThrown') console.error('EXC', m.params.exceptionDetails.exception?.description); });
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 1400, deviceScaleFactor: 3, mobile: false });
await send('Page.enable');
await send('Page.navigate', { url });
await sleep(Number(waitMs));
if (js) { const r = await send('Runtime.evaluate', { expression: js }); if (r.result?.exceptionDetails) console.error('EVAL', r.result.exceptionDetails.exception?.description); await sleep(1500); }
const rr = await send('Runtime.evaluate', { expression: `JSON.stringify((()=>{const s=[...document.querySelectorAll('.screen')].find(e=>e.childElementCount);const r=s.getBoundingClientRect();return {x:r.left+scrollX,y:r.top+scrollY,w:r.width,h:r.height}})())`, returnByValue: true });
const c = JSON.parse(rr.result.result.value);
const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { x: c.x, y: c.y, width: c.w, height: c.h, scale: 1 } });
writeFileSync(out, Buffer.from(shot.result.data, 'base64'));
console.log(out, JSON.stringify(c));
ws.close(); chrome.kill();
