// Loads index.html at a 390 px viewport (headless windows can't go that narrow, so this emulates it over CDP),
// reports any horizontal overflow, and saves a full-page PNG. Usage: node check-narrow.mjs <out.png> [light|dark]
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
const here = path.dirname(fileURLToPath(import.meta.url));
const out = process.argv[2] || path.join(os.tmpdir(), 'ledger-390.png');
const theme = process.argv[3] || 'light';
const page = 'file://' + path.join(here, '..', 'index.html') + '?theme=' + theme;
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'ledger-chrome-'));
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--remote-debugging-port=9334', `--user-data-dir=${profile}`, 'about:blank'], {stdio: 'ignore'});
const sleep = ms => new Promise(r => setTimeout(r, ms));
let list;
for (let i = 0; i < 40; i++) { try { list = await (await fetch('http://127.0.0.1:9334/json/list')).json(); if (list.find(t => t.type === 'page')) break; } catch {} await sleep(250); }
const ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id = 0; const pending = new Map();
ws.onmessage = m => { const d = JSON.parse(m.data); if (pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } };
const send = (method, params) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({id: i, method, params})); });
await send('Emulation.setDeviceMetricsOverride', {width: 390, height: 844, deviceScaleFactor: 1, mobile: true});
await send('Page.navigate', {url: page});
await sleep(3000);
const res = await send('Runtime.evaluate', {returnByValue: true, expression:
  `JSON.stringify({inner:innerWidth,scroll:document.documentElement.scrollWidth,s:getComputedStyle(document.documentElement).getPropertyValue('--s'),
   wide:[...document.querySelectorAll('.pg-head *')].filter(e=>e.getBoundingClientRect().right>innerWidth+0.5).map(e=>e.className||e.tagName).slice(0,8),
   h:document.documentElement.scrollHeight,errors:ERRS})`});
const info = JSON.parse(res.result.result.value);
console.log(JSON.stringify(info));
await send('Emulation.setDeviceMetricsOverride', {width: 390, height: Math.min(info.h, 6000), deviceScaleFactor: 1, mobile: true});
await sleep(500);
const shot = await send('Page.captureScreenshot', {format: 'png'});
fs.writeFileSync(out, Buffer.from(shot.result.data, 'base64'));
ws.close(); chrome.kill();
