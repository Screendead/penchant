// Regenerates node-sealed.json, which test/crypto/journal_cipher_test.dart opens.
import { writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { seal } from '../e2ee.js';

const dek = randomBytes(32);
const docs = [
  { collection: 'vices', docId: 'v1', ownerID: 'alice', fields: { n: 'Coffee ☕', u: 'drink' } },
  { collection: 'activities', docId: 'a1', ownerID: 'alice', viceID: 'v1', fields: { q: 2 } },
].map((d) => ({ ...d, viceID: d.viceID ?? null, enc: seal(dek, d).toString('base64') }));
writeFileSync(
  new URL('./node-sealed.json', import.meta.url),
  JSON.stringify({ dek: dek.toString('base64'), docs }, null, 2) + '\n',
);
