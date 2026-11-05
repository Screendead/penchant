// WCAG 2.x contrast of every text and mark pairing in ../tokens.json, both themes.
// Text needs 4.5:1 (AA); data marks and rules are graphics, held to 3:1 where they carry meaning alone.
// Usage: node check-contrast.mjs   (exits 1 if a text pairing fails)
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const tokens = JSON.parse(fs.readFileSync(path.join(here, '..', 'tokens.json'), 'utf8'));
const lum = hex => {
  const n = parseInt(hex.slice(1), 16);
  return [n >> 16, (n >> 8) & 255, n & 255]
    .map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; })
    .reduce((a, v, i) => a + v * [0.2126, 0.7152, 0.0722][i], 0);
};
const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
let failed = 0;
for (const theme of ['light', 'dark']) {
  const c = tokens.color[theme];
  const text = [
    ['text', c.text, 'bg', c.bg], ['text', c.text, 'surface', c.surface],
    ['muted', c.muted, 'bg', c.bg], ['muted', c.muted, 'surface', c.surface],
    ['onAccent', c.onAccent, 'accent', c.accent],
    ['clearInk', c.clearInk, 'clear', c.clear], ['muted', c.muted, 'clear', c.clear], ['text', c.text, 'clear', c.clear],
    ['error', c.error, 'bg', c.bg], ['error', c.error, 'errorSurface', c.errorSurface],
    ['text', c.text, 'errorSurface', c.errorSurface],
    ...c.dataInk.map((v, i) => [`dataInk[${i}]`, v, 'bg', c.bg]),
  ];
  const marks = c.data.map((v, i) => [`data[${i}]`, v, 'bg', c.bg, c.dataEdge[i] !== 'transparent' ? 'edged' : '']);
  console.log(`\n${theme}`);
  for (const [a, av, b, bv] of text) {
    const r = ratio(av, bv), ok = r >= 4.5; if (!ok) failed++;
    console.log(`  ${ok ? 'pass' : 'FAIL'}  ${r.toFixed(2).padStart(5)}  ${a} ${av} on ${b} ${bv}`);
  }
  for (const [a, av, b, bv, note] of marks) {
    const r = ratio(av, bv);
    console.log(`  ${r >= 3 ? 'mark' : note ? 'edge' : 'LOW '}  ${r.toFixed(2).padStart(5)}  ${a} ${av} on ${b} ${bv}${note ? ' (1 px edge)' : ''}`);
  }
}
process.exit(failed ? 1 : 0);
