// Rules R1: the dual-shape phase of end-to-end encryption (firestore.rules).
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Bytes,
  Timestamp,
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

import { BLOB_LENGTHS, seal } from './e2ee.js';

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  throw new Error('FIRESTORE_EMULATOR_HOST is unset; run via `npm test`.');
}
const separator = emulatorHost.lastIndexOf(':');

const ALICE = 'alice';
const BOB = 'bob';
const createdAt = Timestamp.fromDate(new Date('2026-01-01T12:00:00Z'));
const dek = randomBytes(32);

let testEnv;
const asAlice = () => testEnv.authenticatedContext(ALICE).firestore();
const asBob = () => testEnv.authenticatedContext(BOB).firestore();
const asGuest = () => testEnv.unauthenticatedContext().firestore();

const blob = (n) => Bytes.fromUint8Array(randomBytes(n));
const sealedVice = (docId, overrides = {}) => ({
  enc: Bytes.fromUint8Array(
    seal(dek, { collection: 'vices', docId, ownerID: ALICE, fields: { n: 'Wine', u: 'drink' } }),
  ),
  ownerID: ALICE,
  createdAt: serverTimestamp(),
  archived: false,
  ...overrides,
});
const sealedActivity = (docId, overrides = {}) => ({
  viceID: 'aliceSealedVice',
  enc: Bytes.fromUint8Array(
    seal(dek, {
      collection: 'activities',
      docId,
      ownerID: ALICE,
      viceID: overrides.viceID ?? 'aliceSealedVice',
      fields: { q: 2 },
    }),
  ),
  ownerID: ALICE,
  createdAt: new Date('2026-01-02T08:30:00Z'),
  ...overrides,
});
const keysDoc = (overrides = {}) => ({
  keyId: 'AAAAAAAAAAA',
  check: blob(53),
  recoveryWrap: blob(60),
  createdAt: serverTimestamp(),
  ...overrides,
});

before(async () => {
  testEnv = await initializeTestEnvironment({
    // Its own project, so node --test can run this file beside rules.test.js.
    projectId: 'demo-tracker-e2ee',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
      host: emulatorHost.slice(0, separator),
      port: Number(emulatorHost.slice(separator + 1)),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'vices/alicePlainVice'), {
      name: 'Coffee', unit: 'drink', ownerID: ALICE, createdAt, archived: false,
    });
    await setDoc(doc(db, 'vices/aliceLegacyVice'), {
      name: 'Booze', unit: 'drink', ownerID: ALICE, createdAt,
    });
    await setDoc(doc(db, 'vices/aliceSealedVice'), sealedVice('aliceSealedVice', { createdAt }));
    await setDoc(doc(db, 'vices/bobVice'), {
      name: 'Coffee', unit: 'drink', ownerID: BOB, createdAt, archived: false,
    });
    await setDoc(doc(db, 'activities/alicePlainActivity'), {
      viceID: 'alicePlainVice', quantity: 2, ownerID: ALICE, createdAt,
    });
    await setDoc(doc(db, 'activities/aliceZeroActivity'), {
      viceID: 'alicePlainVice', quantity: 0, ownerID: ALICE, createdAt,
    });
    await setDoc(doc(db, 'activities/aliceOrphanActivity'), {
      viceID: 'gone', quantity: 1, ownerID: ALICE, createdAt,
    });
    await setDoc(
      doc(db, 'activities/aliceSealedActivity'),
      sealedActivity('aliceSealedActivity', { createdAt }),
    );
    await setDoc(doc(db, 'keys/alice'), keysDoc({ createdAt }));
  });
});

after(async () => {
  await testEnv?.cleanup();
});

describe('e2ee R1: vices', () => {
  it('allows a sealed create (add_vice.dart: enc, ownerID, createdAt, archived)', async () => {
    await assertSucceeds(setDoc(doc(asAlice(), 'vices/new'), sealedVice('new')));
  });

  it('still allows the plaintext create, for builds that predate encryption', async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), 'vices/new'), {
        name: 'Tea', unit: 'drink', ownerID: ALICE, createdAt: serverTimestamp(), archived: false,
      }),
    );
  });

  for (const n of BLOB_LENGTHS) {
    it(`allows enc of exactly ${n} bytes and denies ${n - 1} and ${n + 1}`, async () => {
      await assertSucceeds(setDoc(doc(asAlice(), 'vices/ok'), sealedVice('ok', { enc: blob(n) })));
      await assertFails(setDoc(doc(asAlice(), 'vices/short'), sealedVice('short', { enc: blob(n - 1) })));
      await assertFails(setDoc(doc(asAlice(), 'vices/long'), sealedVice('long', { enc: blob(n + 1) })));
    });
  }

  it('denies enc as a base64 string of a valid blob', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'vices/str'), sealedVice('str', { enc: randomBytes(285).toString('base64') })),
    );
  });

  it('denies a mixed shape: enc beside name or unit', async () => {
    await assertFails(setDoc(doc(asAlice(), 'vices/mixed'), sealedVice('mixed', { name: 'Wine' })));
    await assertFails(setDoc(doc(asAlice(), 'vices/mixed'), sealedVice('mixed', { unit: 'drink' })));
  });

  it('denies a sealed vice owned by someone else, or with a missing field', async () => {
    await assertFails(setDoc(doc(asAlice(), 'vices/x'), sealedVice('x', { ownerID: BOB })));
    const { archived, ...noArchived } = sealedVice('x');
    await assertFails(setDoc(doc(asAlice(), 'vices/x'), noArchived));
  });

  it('allows the migration update: plaintext out, enc in, in one write', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'vices/alicePlainVice'), {
        enc: blob(285), name: deleteField(), unit: deleteField(),
      }),
    );
  });

  it('allows migrating a legacy vice and adding its missing archived', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'vices/aliceLegacyVice'), {
        enc: blob(285), name: deleteField(), unit: deleteField(), archived: false,
      }),
    );
  });

  it('denies a migration that leaves plaintext behind', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'vices/alicePlainVice'), { enc: blob(285), unit: deleteField() }),
    );
    await assertFails(updateDoc(doc(asAlice(), 'vices/alicePlainVice'), { enc: blob(285) }));
  });

  it('denies a migration with a bad enc length, or by another user', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'vices/alicePlainVice'), {
        enc: blob(284), name: deleteField(), unit: deleteField(),
      }),
    );
    await assertFails(
      updateDoc(doc(asBob(), 'vices/alicePlainVice'), {
        enc: blob(285), name: deleteField(), unit: deleteField(),
      }),
    );
  });

  it('denies a downgrade: enc out, plaintext back', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'vices/aliceSealedVice'), {
        enc: deleteField(), name: 'Wine', unit: 'drink',
      }),
    );
    await assertFails(updateDoc(doc(asAlice(), 'vices/aliceSealedVice'), { enc: deleteField() }));
  });

  it('denies a second migration that writes plaintext back beside enc', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'vices/aliceSealedVice'), { enc: blob(285), name: 'Wine' }),
    );
    await assertFails(updateDoc(doc(asAlice(), 'vices/aliceSealedVice'), { unit: 'drink' }));
  });

  // Deleting an absent field is no change, so a second migration that only
  // rewrites enc looks exactly like a rename. The migrator skips documents
  // that already have enc (test/crypto/migrator_test.dart); the server can't.
  it('allows re-sealing a sealed vice (a rename), which a repeat migration also looks like', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'vices/aliceSealedVice'), {
        enc: blob(285), name: deleteField(), unit: deleteField(),
      }),
    );
  });

  it('allows archiving a sealed vice without touching enc', async () => {
    await assertSucceeds(updateDoc(doc(asAlice(), 'vices/aliceSealedVice'), { archived: true }));
    await assertFails(updateDoc(doc(asAlice(), 'vices/aliceSealedVice'), { archived: 'yes' }));
  });

  it('allows the vice list queries over sealed and plaintext vices together', async () => {
    const vices = collection(asAlice(), 'vices');
    const all = await assertSucceeds(
      getDocs(query(vices, where('ownerID', '==', ALICE), orderBy('createdAt', 'desc'))),
    );
    if (all.size !== 3) throw new Error(`expected 3 vices, got ${all.size}`);
    await assertSucceeds(
      getDocs(
        query(vices, where('ownerID', '==', ALICE), where('archived', '==', false), orderBy('createdAt', 'desc')),
      ),
    );
  });
});

describe('e2ee R1: activities', () => {
  it('allows a sealed create against an owned vice (record dialog: doc().set())', async () => {
    await assertSucceeds(setDoc(doc(asAlice(), 'activities/new'), sealedActivity('new')));
    await assertSucceeds(
      setDoc(doc(asAlice(), 'activities/new2'), sealedActivity('new2', { viceID: 'alicePlainVice' })),
    );
  });

  for (const n of BLOB_LENGTHS) {
    it(`allows enc of exactly ${n} bytes and denies ${n - 1} and ${n + 1}`, async () => {
      await assertSucceeds(setDoc(doc(asAlice(), 'activities/ok'), sealedActivity('ok', { enc: blob(n) })));
      await assertFails(setDoc(doc(asAlice(), 'activities/s'), sealedActivity('s', { enc: blob(n - 1) })));
      await assertFails(setDoc(doc(asAlice(), 'activities/l'), sealedActivity('l', { enc: blob(n + 1) })));
    });
  }

  it('denies a mixed shape: enc beside quantity', async () => {
    await assertFails(setDoc(doc(asAlice(), 'activities/m'), sealedActivity('m', { quantity: 2 })));
  });

  it("C14 still holds: denies a sealed activity on another user's or a missing vice", async () => {
    await assertFails(setDoc(doc(asAlice(), 'activities/x'), sealedActivity('x', { viceID: 'bobVice' })));
    await assertFails(setDoc(doc(asAlice(), 'activities/x'), sealedActivity('x', { viceID: 'gone' })));
  });

  it('denies a sealed activity owned by someone else, or from a guest', async () => {
    await assertFails(setDoc(doc(asAlice(), 'activities/x'), sealedActivity('x', { ownerID: BOB })));
    await assertFails(setDoc(doc(asGuest(), 'activities/x'), sealedActivity('x')));
  });

  it('allows the migration update, including a zero-quantity and an orphaned legacy activity', async () => {
    for (const id of ['alicePlainActivity', 'aliceZeroActivity', 'aliceOrphanActivity']) {
      await assertSucceeds(
        updateDoc(doc(asAlice(), `activities/${id}`), { enc: blob(93), quantity: deleteField() }),
      );
    }
  });

  it('allows a migration batch of 200 updates (the migrator pages by 200)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const batch = writeBatch(db);
      for (let i = 0; i < 200; i++) {
        batch.set(doc(db, `activities/bulk${i}`), {
          viceID: 'alicePlainVice', quantity: 1, ownerID: ALICE, createdAt,
        });
      }
      await batch.commit();
    });
    const db = asAlice();
    const batch = writeBatch(db);
    for (let i = 0; i < 200; i++) {
      batch.update(doc(db, `activities/bulk${i}`), { enc: blob(93), quantity: deleteField() });
    }
    await assertSucceeds(batch.commit());
  });

  it('denies a migration that keeps quantity', async () => {
    await assertFails(updateDoc(doc(asAlice(), 'activities/alicePlainActivity'), { enc: blob(93) }));
  });

  it('denies a downgrade, and quantity written back beside enc', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'activities/aliceSealedActivity'), { enc: deleteField(), quantity: 2 }),
    );
    await assertFails(updateDoc(doc(asAlice(), 'activities/aliceSealedActivity'), { quantity: 2 }));
  });

  it('allows the editor re-sealing and moving a sealed activity in time', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'activities/aliceSealedActivity'), {
        enc: blob(93), createdAt: new Date('2026-01-03T09:00:00Z'),
      }),
    );
  });

  it('denies moving a sealed activity to another vice, or reassigning it', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'activities/aliceSealedActivity'), { viceID: 'alicePlainVice' }),
    );
    await assertFails(updateDoc(doc(asAlice(), 'activities/aliceSealedActivity'), { ownerID: BOB }));
    await assertFails(updateDoc(doc(asBob(), 'activities/aliceSealedActivity'), { enc: blob(93) }));
  });

  it('allows the day-window query over sealed activities: createdAt stays plaintext', async () => {
    const snapshot = await assertSucceeds(
      getDocs(
        query(
          collection(asAlice(), 'activities'),
          where('viceID', 'in', ['aliceSealedVice', 'alicePlainVice']),
          where('ownerID', '==', ALICE),
          where('createdAt', '>=', Timestamp.fromDate(new Date('2026-01-01T00:00:00Z'))),
          where('createdAt', '<', Timestamp.fromDate(new Date('2026-01-02T00:00:00Z'))),
          orderBy('createdAt', 'desc'),
        ),
      ),
    );
    if (snapshot.size !== 3) throw new Error(`expected 3 activities, got ${snapshot.size}`);
  });
});

describe('e2ee R1: keys/{uid}', () => {
  it('allows the owner to create their keys doc', async () => {
    await assertSucceeds(setDoc(doc(asBob(), 'keys/bob'), keysDoc()));
  });

  it('denies creating keys for another uid, or as a guest', async () => {
    await assertFails(setDoc(doc(asBob(), 'keys/carol'), keysDoc()));
    await assertFails(setDoc(doc(asGuest(), 'keys/bob'), keysDoc()));
  });

  it('denies the wrong shape: sizes, types, extra or missing fields', async () => {
    await assertFails(setDoc(doc(asBob(), 'keys/bob'), keysDoc({ keyId: 'short' })));
    await assertFails(setDoc(doc(asBob(), 'keys/bob'), keysDoc({ check: blob(52) })));
    await assertFails(setDoc(doc(asBob(), 'keys/bob'), keysDoc({ recoveryWrap: blob(61) })));
    await assertFails(setDoc(doc(asBob(), 'keys/bob'), keysDoc({ recoveryWrap: 'x'.repeat(60) })));
    await assertFails(setDoc(doc(asBob(), 'keys/bob'), keysDoc({ dek: blob(32) })));
    const { check, ...noCheck } = keysDoc();
    await assertFails(setDoc(doc(asBob(), 'keys/bob'), noCheck));
  });

  it('is create-only: a second key over the first is denied', async () => {
    await assertFails(setDoc(doc(asAlice(), 'keys/alice'), keysDoc({ keyId: 'BBBBBBBBBBB' })));
  });

  it('keeps keyId and check immutable', async () => {
    await assertFails(updateDoc(doc(asAlice(), 'keys/alice'), { keyId: 'BBBBBBBBBBB' }));
    await assertFails(updateDoc(doc(asAlice(), 'keys/alice'), { check: blob(53) }));
  });

  it('allows re-wrapping under a new recovery key', async () => {
    await assertSucceeds(updateDoc(doc(asAlice(), 'keys/alice'), { recoveryWrap: blob(60) }));
    await assertFails(updateDoc(doc(asAlice(), 'keys/alice'), { recoveryWrap: blob(59) }));
  });

  it('allows the owner to read it and denies a stranger or a guest', async () => {
    await assertSucceeds(getDoc(doc(asAlice(), 'keys/alice')));
    await assertFails(getDoc(doc(asBob(), 'keys/alice')));
    await assertFails(getDoc(doc(asGuest(), 'keys/alice')));
  });

  it('allows the owner to delete it (Start a new journal) and denies a stranger', async () => {
    await assertFails(deleteDoc(doc(asBob(), 'keys/alice')));
    await assertSucceeds(deleteDoc(doc(asAlice(), 'keys/alice')));
  });
});
