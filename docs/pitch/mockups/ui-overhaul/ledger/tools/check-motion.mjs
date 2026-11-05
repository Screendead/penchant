// Drives index.html in real-time headless Chrome (no virtual time, which stalls CSS transitions)
// and samples the animated properties mid-flight. Usage: node check-motion.mjs [profileDir]
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
const here=path.dirname(fileURLToPath(import.meta.url));
const page='file://'+path.join(here,'..','index.html')+'?theme=light';
const profile=process.argv[2]||fs.mkdtempSync(path.join(os.tmpdir(),'ledger-chrome-'));
const chrome=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',['--headless=new','--disable-gpu','--remote-debugging-port=9333',`--user-data-dir=${profile}`,'--window-size=1900,1900',page],{stdio:'ignore'});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let list;for(let i=0;i<40;i++){try{list=await (await fetch('http://127.0.0.1:9333/json/list')).json();if(list.find(t=>t.type==='page'))break}catch{}await sleep(250)}
const ws=new WebSocket(list.find(t=>t.type==='page').webSocketDebuggerUrl);
await new Promise(r=>ws.onopen=r);
let id=0;const pending=new Map();ws.onmessage=m=>{const d=JSON.parse(m.data);if(pending.has(d.id)){pending.get(d.id)(d);pending.delete(d.id)}};
const send=(method,params)=>new Promise(r=>{const i=++id;pending.set(i,r);ws.send(JSON.stringify({id:i,method,params}))});
await sleep(2500);
const test=`(async()=>{const r={};const w=ms=>new Promise(f=>setTimeout(f,ms));const A=APPS;
 const a=A[6];const pw=a.auth.el.querySelector('input[type=password]');pw.value='short';a.auth.el.querySelector('.submit').click();
 await w(700);r.authErrMid=Math.round(a.auth.err.getBoundingClientRect().height);await w(400);r.authErrEnd=Math.round(a.auth.err.getBoundingClientRect().height);
 const dv=A[0].dayView,row=dv.rows[0];const W=()=>Math.round(row.bar.getBoundingClientRect().width);
 const b0=W();row.plusBtn.click();await w(440);const bm=W();r.flashMid=+(+getComputedStyle(row.flash).opacity).toFixed(3);await w(400);r.bar=[b0,bm,W()];
 r.roll=row.roll.cols.map(c=>c.strip.style.transform).join(' ');
 r.undoH=Math.round(A[0].undoHost.getBoundingClientRect().height);r.logLines=dv.log.children.length;
 r.pendingNow=A[0].root.querySelectorAll('.sync.pending:not(.acked)').length;await w(900);r.ackedLater=A[0].root.querySelectorAll('.sync.acked').length;
 A[0].setTab('trends');await w(110);r.tabMid=+getComputedStyle(A[0].tabViews.trends.el).opacity;await w(300);r.tabEnd=+getComputedStyle(A[0].tabViews.trends.el).opacity;
 dv.setDay(3);await w(60);r.dayRowAnims=dv.rows[0].el.getAnimations().length;
 A[2].dayView.rows[0].toggle(true);await w(110);const xh=()=>Math.round(A[2].dayView.rows[0].xp.getBoundingClientRect().height);r.expandMid=xh();await w(300);r.expandEnd=xh();
 r.errors=ERRS;return JSON.stringify(r)})()`;
const res=await send('Runtime.evaluate',{expression:test,awaitPromise:true,returnByValue:true});
console.log(res.result?.result?.value||JSON.stringify(res));
ws.close();chrome.kill();
