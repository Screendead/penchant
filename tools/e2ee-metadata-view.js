// What someone with console access to Firestore still sees under option O1
// (content sealed, timing plaintext). Seeds one sealed journal into the
// Firestore emulator, reads it back over the REST API as the console would,
// and prints the per-vice hour and weekday histograms, the vice and archived
// counts, and one raw document with Firestore's own createTime/updateTime.
//
// Emulator only. Run beside the other agents' ports with:
//   tests/firestore-rules/node_modules/.bin/firebase emulators:exec --only firestore \
//     --project demo-tracker --config <emu-e2ee.json> "node tools/e2ee-metadata-view.js <out-dir>"
import { randomBytes } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { seal } from '../tests/firestore-rules/e2ee.js';

const host = process.env.FIRESTORE_EMULATOR_HOST;
if (!host) throw new Error('FIRESTORE_EMULATOR_HOST is unset; run under emulators:exec.');
const project = process.env.GCLOUD_PROJECT ?? 'demo-tracker';
if (!project.startsWith('demo-')) throw new Error(`refusing non-demo project ${project}`);
const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
// The emulator's documented rules bypass, so seeding needs no Auth emulator.
const headers = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' };
const outDir = process.argv[2];

// Deterministic, so the rendered view is the same on every run. Vice IDs are
// opaque auto-ID lookalikes, as the console would show them; the names here
// are only for the reader of this file.
let state = 7;
const rand = () => ((state = (state * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);

const uid = 'alice';
const dek = randomBytes(32);
const vices = [
  { id: 'Kp3VwZ8sQe1RbT0yXuNa', name: 'Coffee', unit: 'drink', archived: false, hours: [7, 8, 10, 14], perDay: 2.5, days: [0, 1, 2, 3, 4, 5, 6] },
  { id: 'f7HdLq2MzA9cWn4oPjRt', name: 'Wine', unit: 'drink', archived: false, hours: [19, 20, 21, 22], perDay: 1.6, days: [4, 5, 6] },
  { id: 'Ue5BxG1kYs8vTr3mQaZw', name: 'Cigarettes', unit: 'item', archived: false, hours: [11, 13, 16, 18, 22], perDay: 3, days: [0, 1, 2, 3, 4] },
  { id: 'n0RjCw6tHy2LpX9eDbKs', name: 'Vape', unit: 'puff', archived: true, hours: [23, 0, 1], perDay: 0.4, days: [5, 6] },
];

async function put(path, fields) {
  const [collection, id] = path.split('/');
  const response = await fetch(`${base}/${collection}?documentId=${id}`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ fields }),
  });
  if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
}

async function seed() {
  await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, { method: 'DELETE' });
  const start = Date.UTC(2026, 8, 7); // Monday 7 September 2026, eight weeks
  for (const v of vices) {
    await put(`vices/${v.id}`, {
      enc: { bytesValue: seal(dek, { collection: 'vices', docId: v.id, ownerID: uid, fields: { n: v.name, u: v.unit } }).toString('base64') },
      ownerID: { stringValue: uid },
      createdAt: { timestampValue: new Date(start - 86400000).toISOString() },
      archived: { booleanValue: v.archived },
    });
  }
  let n = 0;
  for (let day = 0; day < 56; day++) {
    for (const v of vices) {
      const weekday = (day % 7); // 0 = Monday
      if (!v.days.includes(weekday)) continue;
      const count = Math.floor(v.perDay + rand());
      for (let i = 0; i < count; i++) {
        const hour = v.hours[Math.floor(rand() * v.hours.length)];
        const at = new Date(start + day * 86400000 + hour * 3600000 + Math.floor(rand() * 3600000));
        const id = `a${String(n++).padStart(4, '0')}`;
        await put(`activities/${id}`, {
          viceID: { stringValue: v.id },
          enc: { bytesValue: seal(dek, { collection: 'activities', docId: id, ownerID: uid, viceID: v.id, fields: { q: 1 + Math.floor(rand() * 2) } }).toString('base64') },
          ownerID: { stringValue: uid },
          createdAt: { timestampValue: at.toISOString() },
        });
      }
    }
  }
  return n;
}

async function list(collection) {
  const docs = [];
  let pageToken;
  do {
    const url = new URL(`${base}/${collection}`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const body = await (await fetch(url, { headers })).json();
    docs.push(...(body.documents ?? []));
    pageToken = body.nextPageToken;
  } while (pageToken);
  return docs;
}

const bar = (count, max, width = 24) => '#'.repeat(Math.round((count / Math.max(max, 1)) * width));

function render(viceDocs, activityDocs) {
  const lines = [];
  const out = (s = '') => lines.push(s);
  const idOf = (d) => d.name.split('/').pop();
  const archived = viceDocs.filter((d) => d.fields.archived?.booleanValue).length;

  out('WHAT THE CONSOLE SHOWS UNDER O1 (Firestore emulator, demo-tracker)');
  out('Names, units and amounts are sealed; everything below is plaintext or Firestore metadata.');
  out();
  out(`Vices: ${viceDocs.length} (archived: ${archived}). Entries: ${activityDocs.length}. Owner: ${uid}.`);
  out();

  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const summary = {};
  for (const v of viceDocs) {
    const id = idOf(v);
    const mine = activityDocs.filter((a) => a.fields.viceID.stringValue === id);
    const hours = Array(24).fill(0);
    const days = Array(7).fill(0);
    for (const a of mine) {
      const t = new Date(a.fields.createdAt.timestampValue);
      hours[t.getUTCHours()]++;
      days[(t.getUTCDay() + 6) % 7]++;
    }
    summary[id] = { entries: mine.length, archived: !!v.fields.archived?.booleanValue, hours, days };
    out(`viceID ${id}${v.fields.archived?.booleanValue ? ' (archived)' : ''}: ${mine.length} entries, enc ${Buffer.from(v.fields.enc.bytesValue, 'base64').length} bytes`);
    const hmax = Math.max(...hours);
    out('  hour (UTC)  ' + hours.map((h) => (h === 0 ? '.' : h >= hmax * 0.66 ? '#' : h >= hmax * 0.33 ? '+' : '-')).join(''));
    out('              0         1         2   ');
    out('              012345678901234567890123');
    const dmax = Math.max(...days);
    for (let i = 0; i < 7; i++) out(`  ${weekdays[i]} ${String(days[i]).padStart(4)} ${bar(days[i], dmax)}`);
    out();
  }

  const sample = activityDocs[activityDocs.length - 1];
  out('One activity as the REST API returns it. createTime and updateTime are');
  out("Firestore's own, written by the server and not editable: for a live log they");
  out('equal the moment of logging, so sealing createdAt as well would hide nothing.');
  out(JSON.stringify(sample, null, 2));
  return { text: lines.join('\n'), summary, sample };
}

const seeded = await seed();
const view = render(await list('vices'), await list('activities'));
console.log(view.text);
console.error(`seeded ${seeded} activities`);
if (outDir) {
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, 'metadata-view.txt'), view.text + '\n');
  writeFileSync(join(outDir, 'metadata-view.json'), JSON.stringify({ summary: view.summary, sample: view.sample }, null, 2) + '\n');
}
