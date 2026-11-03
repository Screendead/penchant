// Settles whether `enc` can be a Blob: the rules-language page lists no bytes
// type for `is` (https://firebase.google.com/docs/rules/rules-language), while
// rules.Bytes documents size() (https://firebase.google.com/docs/reference/rules/rules.Bytes).
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { Bytes, doc, setDoc } from 'firebase/firestore';

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  throw new Error('FIRESTORE_EMULATOR_HOST is unset; run via `npm test`.');
}
const separator = emulatorHost.lastIndexOf(':');

// A separate project keeps these throwaway rules away from rules.test.js,
// which node --test runs in parallel.
const rules = `rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /isBytes/{id} {
      allow create: if request.resource.data.enc is bytes
        && request.resource.data.enc.size() == 93;
    }
    match /isString/{id} {
      allow create: if request.resource.data.enc is string;
    }
  }
}`;

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-tracker-bytes-probe',
    firestore: {
      rules,
      host: emulatorHost.slice(0, separator),
      port: Number(emulatorHost.slice(separator + 1)),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

describe('probe: is bytes on a Blob', () => {
  const db = () => testEnv.authenticatedContext('alice').firestore();
  const blob = (n) => Bytes.fromUint8Array(new Uint8Array(n).fill(7));

  it('accepts a 93-byte Blob as bytes and measures it in bytes', async () => {
    await assertSucceeds(setDoc(doc(db(), 'isBytes/a'), { enc: blob(93) }));
    await assertFails(setDoc(doc(db(), 'isBytes/b'), { enc: blob(92) }));
  });

  it('does not treat a Blob as a string, or a string as bytes', async () => {
    await assertFails(setDoc(doc(db(), 'isString/a'), { enc: blob(93) }));
    await assertFails(setDoc(doc(db(), 'isBytes/c'), { enc: 'x'.repeat(93) }));
    assert.ok(true);
  });
});
