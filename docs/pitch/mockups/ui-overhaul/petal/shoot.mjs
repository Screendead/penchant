// Renders index.html in headless Chrome in real time, so springs, timers and
// transitions run as they would for a person. Node 22+ (global WebSocket).
//   node shoot.mjs <out.png> "<query>" <width> <height> [waitMs] [js-to-run-after-load] [scale]
import { spawn } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const [out, query = "", w = "1800", hgt = "2000", waitMs = "3500", js = "", scale = "1"] = process.argv.slice(2);
const page = "file://" + join(dirname(fileURLToPath(import.meta.url)), "index.html") + (query ? "?" + query : "");
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = 9300 + Math.floor(Math.random() * 500);
const proc = spawn(chrome, ["--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), "petal-"))}`, "--hide-scrollbars", `--window-size=${w},${hgt}`, "about:blank"], { stdio: "ignore" });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) { await sleep(150); try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t => t.type === "page"); } catch {} }
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener("open", r));
let id = 0; const pending = new Map();
ws.addEventListener("message", e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send("Emulation.setDeviceMetricsOverride", { width: +w, height: +hgt, deviceScaleFactor: +scale, mobile: false });
await send("Page.enable");
await send("Page.navigate", { url: page });
await sleep(1200);
if (js) { const r = await send("Runtime.evaluate", { expression: js, awaitPromise: true }); if (r.result?.exceptionDetails) console.error(JSON.stringify(r.result.exceptionDetails)); else if (r.result?.result?.value !== undefined) console.log(r.result.result.value); }
await sleep(+waitMs);
const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
writeFileSync(out, Buffer.from(shot.result.data, "base64"));
ws.close(); proc.kill();
