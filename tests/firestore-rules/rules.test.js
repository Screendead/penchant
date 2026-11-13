import assert from 'node:assert/strict';
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
  addDoc,
  collection,
  deleteDoc,
  deleteField,
  doc,
  documentId,
  getCountFromServer,
  getDoc,
  getDocs,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  endAt,
  startAfter,
  startAt,
  updateDoc,
  waitForPendingWrites,
  where,
  writeBatch,
} from 'firebase/firestore';

// Without an explicit host the library falls back to the default port, which may
// belong to an unrelated emulator; only run under `firebase emulators:exec`.
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
  throw new Error('FIRESTORE_EMULATOR_HOST is unset; run via `npm test`.');
}
const separator = emulatorHost.lastIndexOf(':');

const ALICE = 'alice';
const BOB = 'bob';
const createdAt = Timestamp.fromDate(new Date('2026-01-01T12:00:00Z'));

let testEnv;

const asAlice = () => testEnv.authenticatedContext(ALICE).firestore();
const asBob = () => testEnv.authenticatedContext(BOB).firestore();
const asGuest = () => testEnv.unauthenticatedContext().firestore();

const vice = (overrides = {}) => ({
  name: 'Coffee',
  unit: 'drink',
  ownerID: ALICE,
  createdAt: serverTimestamp(),
  archived: false,
  category: 'caffeine',
  ...overrides,
});

const activity = (overrides = {}) => ({
  createdAt: new Date('2026-01-02T08:30:00Z'),
  ownerID: ALICE,
  quantity: 2,
  viceID: 'aliceVice',
  ...overrides,
});

// A Sealer envelope's size: 29 bytes of version, nonce and tag around a padded plaintext.
const bytesOf = (length, fill = 1) => Bytes.fromUint8Array(new Uint8Array(length).fill(fill));
const envelope = bytesOf(29 + 64);

// What the app creates: content only inside `sealed`.
const newVice = (overrides = {}) => ({
  sealed: envelope,
  ownerID: ALICE,
  createdAt: serverTimestamp(),
  archived: false,
  ...overrides,
});

const newActivity = (overrides = {}) => activity({ sealed: envelope, ...overrides });

const without = (data, key) => {
  const copy = { ...data };
  delete copy[key];
  return copy;
};

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-tracker',
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
    await setDoc(doc(db, 'vices/aliceVice'), vice({ createdAt }));
    // admin/populateFirestore.js shape, written before `archived` existed.
    await setDoc(doc(db, 'vices/aliceLegacyVice'), {
      name: 'Booze',
      unit: 'drink',
      ownerID: ALICE,
      createdAt,
    });
    await setDoc(doc(db, 'vices/aliceUnknownUnitVice'), {
      name: 'Snus',
      unit: 'pouch',
      ownerID: ALICE,
      createdAt,
    });
    // Written before names were capped at 60.
    await setDoc(doc(db, 'vices/aliceLongNameVice'), vice({ name: 'x'.repeat(61), createdAt }));
    await setDoc(doc(db, 'vices/bobVice'), vice({ ownerID: BOB, createdAt }));
    await setDoc(doc(db, 'activities/aliceActivity'), activity({ createdAt }));
    await setDoc(doc(db, 'activities/aliceLegacyActivity'), {
      ...activity({ createdAt }),
      note: 'written from the console',
    });
    // Written before quantities had to be positive.
    await setDoc(doc(db, 'activities/aliceZeroActivity'), activity({ quantity: 0, createdAt }));
    // Written before an activity's vice had to exist and belong to its owner.
    await setDoc(doc(db, 'activities/aliceOrphanActivity'), activity({ viceID: 'gone', createdAt }));
    await setDoc(
      doc(db, 'activities/aliceForeignViceActivity'),
      activity({ viceID: 'bobVice', createdAt }),
    );
    await setDoc(
      doc(db, 'activities/bobActivity'),
      activity({ ownerID: BOB, viceID: 'bobVice', createdAt }),
    );
  });
});

after(async () => {
  await testEnv?.cleanup();
});

describe('vices', () => {
  describe('create', () => {
    it('allows the sealed shape TrackerWrites.addVice writes, with a server timestamp', async () => {
      await assertSucceeds(addDoc(collection(asAlice(), 'vices'), newVice()));
      await assertSucceeds(setDoc(doc(collection(asAlice(), 'vices')), newVice()));
    });

    it('allows an envelope at either padding bound (64 and 4096 bytes of plaintext)', async () => {
      for (const sealed of [bytesOf(29 + 64), bytesOf(29 + 4096)]) {
        await assertSucceeds(addDoc(collection(asAlice(), 'vices'), newVice({ sealed })));
      }
    });

    it('denies a plaintext vice, however valid its content', async () => {
      const plaintext = [
        vice(),
        without(vice(), 'category'),
        ...['item', 'time', 'puff', 'drink', 'minute', 'hour'].map((unit) => vice({ unit })),
      ];
      for (const data of plaintext) {
        await assertFails(addDoc(collection(asAlice(), 'vices'), data));
      }
    });

    it('denies plaintext content beside the envelope', async () => {
      for (const content of [{ name: 'Coffee' }, { unit: 'drink' }, { category: 'caffeine' }]) {
        await assertFails(addDoc(collection(asAlice(), 'vices'), newVice(content)));
      }
    });

    it('denies creating a vice owned by someone else', async () => {
      await assertFails(addDoc(collection(asAlice(), 'vices'), newVice({ ownerID: BOB })));
    });

    it('denies unauthenticated creates', async () => {
      await assertFails(addDoc(collection(asGuest(), 'vices'), newVice()));
    });

    it('denies a missing required field', async () => {
      for (const key of ['sealed', 'ownerID', 'createdAt', 'archived']) {
        await assertFails(addDoc(collection(asAlice(), 'vices'), without(newVice(), key)));
      }
    });

    it('denies an unknown field', async () => {
      await assertFails(addDoc(collection(asAlice(), 'vices'), newVice({ colour: 'red' })));
    });

    it('denies wrong types and invalid values', async () => {
      const bad = [
        { createdAt: '2026-01-01' },
        { archived: 'false' },
        { ownerID: null },
        { sealed: 'not bytes' },
        { sealed: bytesOf(29) },
        { sealed: bytesOf(4126) },
      ];
      for (const overrides of bad) {
        await assertFails(addDoc(collection(asAlice(), 'vices'), newVice(overrides)));
      }
    });
  });

  describe('read', () => {
    it('allows the owner to get their vice', async () => {
      await assertSucceeds(getDoc(doc(asAlice(), 'vices/aliceVice')));
    });

    it('allows the owner to get a legacy vice', async () => {
      await assertSucceeds(getDoc(doc(asAlice(), 'vices/aliceLegacyVice')));
    });

    it('allows the owner to get a legacy vice whose name is over 60', async () => {
      await assertSucceeds(getDoc(doc(asAlice(), 'vices/aliceLongNameVice')));
    });

    it('allows the vice list query', async () => {
      await assertSucceeds(
        getDocs(
          query(
            collection(asAlice(), 'vices'),
            orderBy('createdAt', 'desc'),
            where('ownerID', '==', ALICE),
          ),
        ),
      );
    });

    it('allows the unarchived vice list query', async () => {
      await assertSucceeds(
        getDocs(
          query(
            collection(asAlice(), 'vices'),
            where('ownerID', '==', ALICE),
            where('archived', '==', false),
            orderBy('createdAt', 'desc'),
          ),
        ),
      );
    });

    it('denies a query not constrained to the caller', async () => {
      await assertFails(getDocs(collection(asAlice(), 'vices')));
      await assertFails(
        getDocs(query(collection(asAlice(), 'vices'), where('ownerID', '==', BOB))),
      );
    });

    it('denies a non-owner get', async () => {
      await assertFails(getDoc(doc(asBob(), 'vices/aliceVice')));
    });

    it('denies an unauthenticated get', async () => {
      await assertFails(getDoc(doc(asGuest(), 'vices/aliceVice')));
    });
  });

  describe('update', () => {
    it('allows the owner to archive and unarchive', async () => {
      const ref = doc(asAlice(), 'vices/aliceVice');
      await assertSucceeds(updateDoc(ref, { archived: true }));
      await assertSucceeds(updateDoc(ref, { archived: false }));
    });

    it('allows archiving a legacy vice that lacks `archived`', async () => {
      await assertSucceeds(updateDoc(doc(asAlice(), 'vices/aliceLegacyVice'), { archived: true }));
    });

    it('allows archiving a vice whose unit is outside the enum', async () => {
      await assertSucceeds(
        updateDoc(doc(asAlice(), 'vices/aliceUnknownUnitVice'), { archived: true }),
      );
    });

    it('allows archiving or changing the unit of a vice whose name is over 60', async () => {
      const ref = doc(asAlice(), 'vices/aliceLongNameVice');
      await assertSucceeds(updateDoc(ref, { archived: true }));
      await assertSucceeds(updateDoc(ref, { unit: 'item' }));
      await assertSucceeds(updateDoc(ref, { name: 'x'.repeat(60) }));
    });

    // Mirrors lib/data/limits.dart; the app writes these only sealed.
    it('bounds a plaintext unit label, its singular, cost per unit and currency', async () => {
      const ref = doc(asAlice(), 'vices/aliceVice');
      await assertSucceeds(updateDoc(ref, { unitLabel: 'x'.repeat(20) }));
      await assertSucceeds(updateDoc(ref, { unitSingular: 'x'.repeat(20) }));
      await assertSucceeds(updateDoc(ref, { costPerUnit: 2.5 }));
      await assertSucceeds(updateDoc(ref, { costPerUnit: 100000 }));
      await assertSucceeds(updateDoc(ref, { currency: 'GBP' }));
      for (const bad of [
        { unitLabel: '' },
        { unitLabel: 'x'.repeat(21) },
        { unitLabel: 3 },
        { unitSingular: '' },
        { unitSingular: 'x'.repeat(21) },
        { unitSingular: 3 },
        { costPerUnit: 0 },
        { costPerUnit: -1 },
        { costPerUnit: 100001 },
        { costPerUnit: '2' },
        { currency: 'gbp' },
        { currency: 'GBPX' },
        { currency: 'GB' },
      ]) {
        await assertFails(updateDoc(ref, bad));
      }
      await assertFails(updateDoc(ref, { unitLabel: deleteField() }));
      await assertFails(updateDoc(ref, { unitSingular: deleteField() }));
    });

    it('denies renaming to more than 60 characters', async () => {
      await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), { name: 'x'.repeat(61) }));
      await assertFails(
        updateDoc(doc(asAlice(), 'vices/aliceLongNameVice'), { name: 'x'.repeat(62) }),
      );
    });

    // Pins the unit lib/data/limits.dart measures in: each emoji is two UTF-16 code units.
    it('counts a new name in UTF-16 code units', async () => {
      const ref = doc(asAlice(), 'vices/aliceVice');
      await assertSucceeds(updateDoc(ref, { name: '😀'.repeat(30) }));
      await assertFails(updateDoc(ref, { name: '😀'.repeat(31) }));
    });

    it('denies a non-bool archived', async () => {
      await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), { archived: 'yes' }));
    });

    it('allows adding a category to a legacy vice and changing it', async () => {
      const ref = doc(asAlice(), 'vices/aliceLegacyVice');
      await assertSucceeds(updateDoc(ref, { category: 'alcohol' }));
      await assertSucceeds(updateDoc(ref, { category: 'other' }));
      await assertSucceeds(
        updateDoc(doc(asAlice(), 'vices/aliceUnknownUnitVice'), { category: 'nicotine' }),
      );
    });

    it('denies an invalid category on update', async () => {
      const ref = doc(asAlice(), 'vices/aliceVice');
      await assertFails(updateDoc(ref, { category: 'sugar' }));
      await assertFails(updateDoc(ref, { category: 1 }));
      await assertFails(updateDoc(doc(asBob(), 'vices/aliceVice'), { category: 'food' }));
    });

    it('denies an invalid rename', async () => {
      await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), { name: '' }));
      await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), { unit: 'pouch' }));
    });

    it('denies changing createdAt or adding a field', async () => {
      const ref = doc(asAlice(), 'vices/aliceVice');
      await assertFails(updateDoc(ref, { createdAt: Timestamp.now() }));
      await assertFails(updateDoc(ref, { colour: 'red' }));
    });

    it('denies the owner reassigning ownerID', async () => {
      const ref = doc(asAlice(), 'vices/aliceVice');
      await assertFails(updateDoc(ref, { ownerID: BOB }));
      await assertFails(setDoc(ref, vice({ ownerID: BOB, createdAt })));
    });

    it('denies a non-owner update', async () => {
      await assertFails(updateDoc(doc(asBob(), 'vices/aliceVice'), { archived: true }));
    });

    it("denies a non-owner overwriting with their own ownerID", async () => {
      await assertFails(setDoc(doc(asBob(), 'vices/aliceVice'), vice({ ownerID: BOB })));
      await assertFails(updateDoc(doc(asBob(), 'vices/aliceVice'), { ownerID: BOB }));
    });

    it('denies an unauthenticated update', async () => {
      await assertFails(updateDoc(doc(asGuest(), 'vices/aliceVice'), { archived: true }));
    });
  });

  describe('delete', () => {
    it('allows the owner to delete, including a legacy vice', async () => {
      await assertSucceeds(deleteDoc(doc(asAlice(), 'vices/aliceVice')));
      await assertSucceeds(deleteDoc(doc(asAlice(), 'vices/aliceLegacyVice')));
      await assertSucceeds(deleteDoc(doc(asAlice(), 'vices/aliceLongNameVice')));
    });

    it('denies a non-owner delete', async () => {
      await assertFails(deleteDoc(doc(asBob(), 'vices/aliceVice')));
    });

    it('denies an unauthenticated delete', async () => {
      await assertFails(deleteDoc(doc(asGuest(), 'vices/aliceVice')));
    });

    // resource is null, so ownsExisting() cannot hold: a repeat delete is denied, not a no-op.
    it('denies deleting a missing document, even its last owner', async () => {
      const ref = doc(asAlice(), 'vices/aliceVice');
      await assertSucceeds(deleteDoc(ref));
      await assertFails(deleteDoc(ref));
    });
  });
});

describe('activities', () => {
  describe('create', () => {
    it('allows the sealed shape TrackerWrites.recordActivity writes, with add()', async () => {
      await assertSucceeds(addDoc(collection(asAlice(), 'activities'), newActivity()));
    });

    it('allows the same shape written with doc().set()', async () => {
      await assertSucceeds(setDoc(doc(collection(asAlice(), 'activities')), newActivity()));
    });

    it('allows an envelope at either padding bound (64 and 4096 bytes of plaintext)', async () => {
      for (const sealed of [bytesOf(29 + 64), bytesOf(29 + 4096)]) {
        await assertSucceeds(addDoc(collection(asAlice(), 'activities'), newActivity({ sealed })));
      }
    });

    it('allows a quantity of 1', async () => {
      await assertSucceeds(addDoc(collection(asAlice(), 'activities'), newActivity({ quantity: 1 })));
    });

    it('denies a zero or negative quantity', async () => {
      await assertFails(addDoc(collection(asAlice(), 'activities'), newActivity({ quantity: 0 })));
      await assertFails(addDoc(collection(asAlice(), 'activities'), newActivity({ quantity: -1 })));
    });

    it("allows recording against the owner's legacy or archived vice", async () => {
      await assertSucceeds(
        addDoc(collection(asAlice(), 'activities'), newActivity({ viceID: 'aliceLegacyVice' })),
      );
      await assertSucceeds(updateDoc(doc(asAlice(), 'vices/aliceVice'), { archived: true }));
      await assertSucceeds(addDoc(collection(asAlice(), 'activities'), newActivity()));
    });

    it("denies recording against another user's vice", async () => {
      await assertFails(
        addDoc(collection(asAlice(), 'activities'), newActivity({ viceID: 'bobVice' })),
      );
    });

    it('denies recording against a vice that does not exist', async () => {
      for (const viceID of ['gone', '', 'aliceVice/activities/x']) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), newActivity({ viceID })));
      }
    });

    it('denies recording against a vice deleted earlier', async () => {
      await assertSucceeds(deleteDoc(doc(asAlice(), 'vices/aliceVice')));
      await assertFails(addDoc(collection(asAlice(), 'activities'), newActivity()));
    });

    // get() reads committed state; seeing the batch's own vice would need getAfter().
    it('denies a batch that creates the vice and its first activity together', async () => {
      const db = asAlice();
      const viceRef = doc(collection(db, 'vices'));
      const batch = writeBatch(db);
      batch.set(viceRef, newVice());
      batch.set(doc(collection(db, 'activities')), newActivity({ viceID: viceRef.id }));
      await assertFails(batch.commit());
    });

    it('denies creating an activity owned by someone else', async () => {
      await assertFails(addDoc(collection(asAlice(), 'activities'), newActivity({ ownerID: BOB })));
    });

    it('denies unauthenticated creates', async () => {
      await assertFails(addDoc(collection(asGuest(), 'activities'), newActivity()));
    });

    it('denies a missing required field', async () => {
      for (const key of ['viceID', 'quantity', 'ownerID', 'createdAt', 'sealed']) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), without(newActivity(), key)));
      }
    });

    it('denies an unknown field', async () => {
      await assertFails(addDoc(collection(asAlice(), 'activities'), newActivity({ note: 'hi' })));
    });

    it('allows an optional positive amount, whole or decimal', async () => {
      for (const amount of [1.5, 0.25, 2]) {
        await assertSucceeds(
          addDoc(collection(asAlice(), 'activities'), newActivity({ amount, quantity: Math.ceil(amount) })),
        );
      }
    });

    it('denies a zero, negative or non-number amount', async () => {
      for (const amount of [0, -1.5, '1.5', null, true]) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), newActivity({ amount })));
      }
    });

    it('denies wrong types', async () => {
      const bad = [
        { quantity: 2.5 },
        { quantity: '2' },
        { viceID: 7 },
        { createdAt: '2026-01-02' },
        { sealed: 'not bytes' },
        { sealed: bytesOf(29) },
        { sealed: bytesOf(4126) },
      ];
      for (const overrides of bad) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), newActivity(overrides)));
      }
    });

    it('denies a plaintext activity, with or without triggers', async () => {
      for (const data of [activity(), activity({ triggers: ['work/meeting'] }), activity({ triggers: [] })]) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), data));
      }
    });

    it('denies plaintext triggers beside the envelope, valid or not', async () => {
      for (const triggers of [[], ['work/meeting'], ['feeling/stressed', 'Late train'], [''], 'work/meeting']) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), newActivity({ triggers })));
      }
    });
  });

  describe('read', () => {
    it('allows the owner to get their activity', async () => {
      await assertSucceeds(getDoc(doc(asAlice(), 'activities/aliceActivity')));
    });

    it('allows the owner to get a legacy activity with a zero quantity', async () => {
      await assertSucceeds(getDoc(doc(asAlice(), 'activities/aliceZeroActivity')));
    });

    it("allows the owner to get a legacy activity whose vice is missing or someone else's", async () => {
      await assertSucceeds(getDoc(doc(asAlice(), 'activities/aliceOrphanActivity')));
      await assertSucceeds(getDoc(doc(asAlice(), 'activities/aliceForeignViceActivity')));
    });

    it('allows the day-window query, across every vice', async () => {
      const day = await assertSucceeds(
        getDocs(
          query(
            collection(asAlice(), 'activities'),
            where('ownerID', '==', ALICE),
            where('createdAt', '>=', Timestamp.fromDate(new Date('2026-01-01T00:00:00Z'))),
            where('createdAt', '<', Timestamp.fromDate(new Date('2026-01-02T00:00:00Z'))),
            orderBy('createdAt', 'desc'),
          ),
        ),
      );
      assert.ok(day.docs.length > 0);
      assert.ok(day.docs.every((d) => d.get('ownerID') === ALICE));
    });

    it('allows a page of the history query', async () => {
      await assertSucceeds(
        getDocs(
          query(
            collection(asAlice(), 'activities'),
            where('viceID', '==', 'aliceVice'),
            where('ownerID', '==', ALICE),
            orderBy('createdAt', 'desc'),
            limit(51),
          ),
        ),
      );
    });

    it("allows counting a vice's activities on the server", async () => {
      const counted = await assertSucceeds(
        getCountFromServer(
          query(
            collection(asAlice(), 'activities'),
            where('viceID', '==', 'aliceVice'),
            where('ownerID', '==', ALICE),
          ),
        ),
      );
      assert.ok(counted.data().count > 0);
    });

    it("denies counting someone else's activities", async () => {
      await assertFails(
        getCountFromServer(
          query(collection(asAlice(), 'activities'), where('viceID', '==', 'bobVice')),
        ),
      );
    });

    it("fails the editor's listener once its activity is deleted", async () => {
      const db = asAlice();
      const seen = [];
      const errors = [];
      let first;
      const firstSnapshot = new Promise((resolve) => {
        first = resolve;
      });
      const unsubscribe = onSnapshot(
        doc(db, 'activities/aliceActivity'),
        { includeMetadataChanges: true },
        (snapshot) => {
          seen.push({ exists: snapshot.exists(), fromCache: snapshot.metadata.fromCache });
          first();
        },
        (error) => errors.push(error.code),
      );
      try {
        await firstSnapshot;
        // Resolves on the server's acknowledgement, not the local write.
        await deleteDoc(doc(db, 'activities/aliceActivity'));
        await waitForPendingWrites(db);
        await new Promise((resolve) => setTimeout(resolve, 500));
      } finally {
        unsubscribe();
      }
      // The local delete reports the document gone; the server then re-runs the
      // get rule against a missing document and denies it.
      assert.equal(seen[0].exists, true);
      assert.equal(seen.at(-1).exists, false);
      assert.deepEqual(errors, ['permission-denied']);
    });

    it('denies getting a missing activity, even to a signed-in user', async () => {
      await assertFails(getDoc(doc(asAlice(), 'activities/missing')));
      await assertFails(
        getDocs(
          query(
            collection(asAlice(), 'activities'),
            where('ownerID', '==', ALICE),
            where(documentId(), '==', 'missing'),
          ),
        ),
      );
    });

    // TrackerWrites.serverDocument: how a launch checks what became of a write
    // an earlier launch queued, where a get of a missing document is denied.
    for (const [path, id] of [
      ['vices', 'aliceVice'],
      ['activities', 'aliceActivity'],
    ]) {
      it(`allows the owner to look up one ${path} document by id, there or missing`, async () => {
        const lookUp = (documentID) =>
          getDocs(
            query(
              collection(asAlice(), path),
              where('ownerID', '==', ALICE),
              orderBy(documentId()),
              startAt(documentID),
              endAt(documentID),
            ),
          );
        assert.equal((await assertSucceeds(lookUp(id))).size, 1);
        assert.equal((await assertSucceeds(lookUp('missing'))).size, 0);
      });
    }

    it('denies a query not constrained to the caller', async () => {
      await assertFails(getDocs(collection(asAlice(), 'activities')));
      await assertFails(
        getDocs(
          query(
            collection(asAlice(), 'activities'),
            where('viceID', '==', 'bobVice'),
            where('ownerID', '==', BOB),
          ),
        ),
      );
    });

    it('denies a non-owner get', async () => {
      await assertFails(getDoc(doc(asBob(), 'activities/aliceActivity')));
    });

    it('denies an unauthenticated get', async () => {
      await assertFails(getDoc(doc(asGuest(), 'activities/aliceActivity')));
    });
  });

  describe('update', () => {
    it('allows the shape the activity editor writes', async () => {
      await assertSucceeds(
        updateDoc(doc(asAlice(), 'activities/aliceActivity'), {
          createdAt: new Date('2026-01-03T09:00:00Z'),
          quantity: 5,
        }),
      );
    });

    it("allows editing a legacy activity whose vice is missing or someone else's", async () => {
      for (const id of ['aliceOrphanActivity', 'aliceForeignViceActivity']) {
        const ref = doc(asAlice(), `activities/${id}`);
        await assertSucceeds(updateDoc(ref, { quantity: 4 }));
        await assertSucceeds(updateDoc(ref, { createdAt: new Date('2026-01-03T09:00:00Z') }));
      }
    });

    it('allows editing a legacy activity carrying an extra field', async () => {
      await assertSucceeds(
        updateDoc(doc(asAlice(), 'activities/aliceLegacyActivity'), { quantity: 3 }),
      );
    });

    it('allows moving a legacy zero-quantity activity, or fixing its quantity', async () => {
      const ref = doc(asAlice(), 'activities/aliceZeroActivity');
      await assertSucceeds(updateDoc(ref, { createdAt: new Date('2026-01-03T09:00:00Z') }));
      await assertSucceeds(updateDoc(ref, { quantity: 1 }));
    });

    it('allows the editor writing back an unchanged zero quantity with a new time', async () => {
      await assertSucceeds(
        updateDoc(doc(asAlice(), 'activities/aliceZeroActivity'), {
          createdAt: new Date('2026-01-03T09:00:00Z'),
          quantity: 0,
        }),
      );
    });

    it('denies changing a quantity to zero or below', async () => {
      const ref = doc(asAlice(), 'activities/aliceActivity');
      await assertFails(updateDoc(ref, { quantity: 0 }));
      await assertFails(updateDoc(ref, { quantity: -1 }));
      await assertFails(updateDoc(doc(asAlice(), 'activities/aliceZeroActivity'), { quantity: -1 }));
    });

    it('allows adding, changing or removing an amount', async () => {
      const ref = doc(asAlice(), 'activities/aliceActivity');
      await assertSucceeds(updateDoc(ref, { amount: 1.5, quantity: 2 }));
      await assertSucceeds(updateDoc(ref, { amount: 0.75 }));
      await assertSucceeds(updateDoc(ref, { amount: deleteField() }));
    });

    it('allows adding an amount to a legacy activity', async () => {
      for (const id of ['aliceZeroActivity', 'aliceLegacyActivity', 'aliceOrphanActivity']) {
        await assertSucceeds(updateDoc(doc(asAlice(), `activities/${id}`), { amount: 2.5 }));
      }
    });

    it('denies changing an amount to zero, below or a non-number', async () => {
      const ref = doc(asAlice(), 'activities/aliceActivity');
      for (const amount of [0, -0.5, '2', null]) {
        await assertFails(updateDoc(ref, { amount }));
      }
    });

    it('denies wrong types', async () => {
      const ref = doc(asAlice(), 'activities/aliceActivity');
      await assertFails(updateDoc(ref, { quantity: '3' }));
      await assertFails(updateDoc(ref, { quantity: 1.5 }));
      await assertFails(updateDoc(ref, { createdAt: 'yesterday' }));
    });

    it('allows setting, changing and clearing triggers', async () => {
      const ref = doc(asAlice(), 'activities/aliceActivity');
      await assertSucceeds(updateDoc(ref, { triggers: ['work/meeting', 'Late train'] }));
      await assertSucceeds(updateDoc(ref, { triggers: ['body/tired'], quantity: 3 }));
      await assertSucceeds(updateDoc(ref, { triggers: [] }));
    });

    it('allows adding triggers to legacy activities that never had them', async () => {
      for (const id of ['aliceLegacyActivity', 'aliceZeroActivity', 'aliceOrphanActivity']) {
        await assertSucceeds(
          updateDoc(doc(asAlice(), `activities/${id}`), { triggers: ['routine/morning'] }),
        );
      }
    });

    it('denies invalid triggers on update', async () => {
      const ref = doc(asAlice(), 'activities/aliceActivity');
      for (const triggers of [
        'work',
        [7],
        [''],
        ['x'.repeat(61)],
        Array.from({ length: 11 }, (_, i) => `t${i}`),
      ]) {
        await assertFails(updateDoc(ref, { triggers }));
      }
    });

    it('denies moving the activity to another vice', async () => {
      await assertFails(updateDoc(doc(asAlice(), 'activities/aliceActivity'), { viceID: 'other' }));
    });

    it('denies the owner reassigning ownerID', async () => {
      const ref = doc(asAlice(), 'activities/aliceActivity');
      await assertFails(updateDoc(ref, { ownerID: BOB }));
      await assertFails(setDoc(ref, activity({ ownerID: BOB })));
    });

    it('denies a non-owner update', async () => {
      await assertFails(updateDoc(doc(asBob(), 'activities/aliceActivity'), { quantity: 9 }));
    });

    it("denies a non-owner overwriting with their own ownerID", async () => {
      await assertFails(
        setDoc(doc(asBob(), 'activities/aliceActivity'), activity({ ownerID: BOB })),
      );
    });

    it('denies an unauthenticated update', async () => {
      await assertFails(updateDoc(doc(asGuest(), 'activities/aliceActivity'), { quantity: 9 }));
    });
  });

  describe('delete', () => {
    it('allows Undo: the owner deletes the activity they just recorded', async () => {
      const ref = doc(collection(asAlice(), 'activities'));
      await assertSucceeds(setDoc(ref, newActivity()));
      await assertSucceeds(deleteDoc(ref));
    });

    it('allows the owner to delete an existing activity', async () => {
      await assertSucceeds(deleteDoc(doc(asAlice(), 'activities/aliceActivity')));
      await assertSucceeds(deleteDoc(doc(asAlice(), 'activities/aliceLegacyActivity')));
      await assertSucceeds(deleteDoc(doc(asAlice(), 'activities/aliceZeroActivity')));
      await assertSucceeds(deleteDoc(doc(asAlice(), 'activities/aliceOrphanActivity')));
      await assertSucceeds(deleteDoc(doc(asAlice(), 'activities/aliceForeignViceActivity')));
    });

    it('denies a non-owner delete', async () => {
      await assertFails(deleteDoc(doc(asBob(), 'activities/aliceActivity')));
    });

    it('denies an unauthenticated delete', async () => {
      await assertFails(deleteDoc(doc(asGuest(), 'activities/aliceActivity')));
    });

    // resource is null, so ownsExisting() cannot hold: a repeat delete is denied, not a no-op.
    it('denies deleting a missing document, even its last owner', async () => {
      const ref = doc(asAlice(), 'activities/aliceActivity');
      await assertSucceeds(deleteDoc(ref));
      await assertFails(deleteDoc(ref));
    });
  });
});

// The query shapes lib/account/account.dart uses for export and deletion.
describe('account export and deletion', () => {
  const owned = (db, collectionName) =>
    query(collection(db, collectionName), where('ownerID', '==', ALICE));

  it('allows the export query, one page after another, and returns only the owner\'s documents', async () => {
    const ids = [];
    let page = query(owned(asAlice(), 'activities'), orderBy(documentId()), limit(2));
    for (;;) {
      const snapshot = await assertSucceeds(getDocs(page));
      ids.push(...snapshot.docs.map((d) => d.id));
      if (snapshot.docs.length < 2) break;
      page = query(
        owned(asAlice(), 'activities'),
        orderBy(documentId()),
        startAfter(snapshot.docs.at(-1)),
        limit(2),
      );
    }
    assert.deepEqual(ids, [
      'aliceActivity',
      'aliceForeignViceActivity',
      'aliceLegacyActivity',
      'aliceOrphanActivity',
      'aliceZeroActivity',
    ]);
  });

  it('allows a batch deleting every document the owner holds, legacy ones included', async () => {
    const db = asAlice();
    for (const collectionName of ['activities', 'vices']) {
      const snapshot = await assertSucceeds(getDocs(query(owned(db, collectionName), limit(500))));
      const batch = writeBatch(db);
      snapshot.docs.forEach((d) => batch.delete(d.ref));
      await assertSucceeds(batch.commit());
      assert.equal((await getDocs(owned(db, collectionName))).size, 0);
    }
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      assert.ok((await getDoc(doc(admin, 'vices/bobVice'))).exists());
      assert.ok((await getDoc(doc(admin, 'activities/bobActivity'))).exists());
    });
  });

  it('denies a deletion batch that reaches another owner\'s document', async () => {
    const db = asAlice();
    const batch = writeBatch(db);
    batch.delete(doc(db, 'vices/aliceVice'));
    batch.delete(doc(db, 'vices/bobVice'));
    await assertFails(batch.commit());
  });
});

// lib/crypto/plaintext_migrator.dart's one update per legacy document. An
// activity seals only its triggers; its quantity and amount stay plaintext.
describe('sealing plaintext on first launch', () => {
  const sealed = (fill = 1) => Bytes.fromUint8Array(new Uint8Array(29 + 64).fill(fill));
  // Deleting a field the document lacks changes nothing, as the migrator's
  // update for a vice without a category does not delete one.
  const sealVice = (extra = {}) => ({
    sealed: sealed(),
    name: deleteField(),
    unit: deleteField(),
    category: deleteField(),
    ...extra,
  });

  it('seals a legacy activity\'s triggers, keeping its quantity and amount', async () => {
    await testEnv.withSecurityRulesDisabled((context) =>
      setDoc(doc(context.firestore(), 'activities/aliceLegacyTriggered'), {
        viceID: 'aliceVice',
        quantity: 0,
        amount: 0.5,
        ownerID: ALICE,
        createdAt,
        triggers: ['social'],
      }),
    );
    const ref = doc(asAlice(), 'activities/aliceLegacyTriggered');
    await assertFails(updateDoc(ref, { sealed: sealed() }));
    await assertSucceeds(updateDoc(ref, { sealed: sealed(), triggers: deleteField() }));
    const stored = (await getDoc(ref)).data();
    assert.deepEqual(Object.keys(stored).sort(), [
      'amount',
      'createdAt',
      'ownerID',
      'quantity',
      'sealed',
      'viceID',
    ]);
  });

  it('allows the owner to seal a vice, removing name, unit and category', async () => {
    const ref = doc(asAlice(), 'vices/aliceVice');
    await assertSucceeds(updateDoc(ref, sealVice()));
    const stored = (await getDoc(ref)).data();
    assert.deepEqual(Object.keys(stored).sort(), ['archived', 'createdAt', 'ownerID', 'sealed']);
  });

  it('allows sealing legacy vices: no `archived`, a unit outside the enum, a long name', async () => {
    for (const id of ['aliceLegacyVice', 'aliceUnknownUnitVice', 'aliceLongNameVice']) {
      await assertSucceeds(updateDoc(doc(asAlice(), `vices/${id}`), sealVice()));
    }
  });

  it('allows sealing a vice that has no unit', async () => {
    await testEnv.withSecurityRulesDisabled((context) =>
      setDoc(doc(context.firestore(), 'vices/aliceNoUnit'), {
        name: 'Tea',
        ownerID: ALICE,
        createdAt,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'vices/aliceNoUnit'), { sealed: sealed(), name: deleteField() }),
    );
  });

  it('allows sealing in a batch, as the migrator commits', async () => {
    const db = asAlice();
    const batch = writeBatch(db);
    batch.update(doc(db, 'vices/aliceVice'), sealVice());
    batch.update(doc(db, 'vices/aliceLegacyVice'), sealVice());
    await assertSucceeds(batch.commit());
  });

  it('keeps a plaintext and a sealed vice of one user readable side by side', async () => {
    await assertSucceeds(updateDoc(doc(asAlice(), 'vices/aliceVice'), sealVice()));
    await assertSucceeds(getDoc(doc(asAlice(), 'vices/aliceVice')));
    await assertSucceeds(getDoc(doc(asAlice(), 'vices/aliceLegacyVice')));
    await assertSucceeds(updateDoc(doc(asAlice(), 'vices/aliceLegacyVice'), { name: 'Tea' }));
  });

  // lib/writes/tracker_writes.dart's sealed update deletes every content
  // field, the unit label and price included, whether or not they exist.
  it('allows a sealed update that also deletes an absent unit label and price', async () => {
    await assertSucceeds(updateDoc(doc(asAlice(), 'vices/aliceVice'), sealVice()));
    await assertSucceeds(
      updateDoc(
        doc(asAlice(), 'vices/aliceVice'),
        sealVice({
          unitLabel: deleteField(),
          unitSingular: deleteField(),
          costPerUnit: deleteField(),
          currency: deleteField(),
        }),
      ),
    );
  });

  it('denies a unit label or price in plaintext beside the envelope', async () => {
    await assertSucceeds(updateDoc(doc(asAlice(), 'vices/aliceVice'), sealVice()));
    for (const extra of [{ unitLabel: 'cups' }, { unitSingular: 'cup' }, { costPerUnit: 4.5 }, { currency: 'GBP' }]) {
      await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), extra));
    }
  });

  it('converts a vice holding a plaintext unit label and price', async () => {
    await testEnv.withSecurityRulesDisabled((context) =>
      setDoc(doc(context.firestore(), 'vices/alicePriced'), {
        ...vice({ createdAt }),
        unitLabel: 'cups',
        unitSingular: 'cup',
        costPerUnit: 3.2,
        currency: 'GBP',
      }),
    );
    const ref = doc(asAlice(), 'vices/alicePriced');
    await assertFails(updateDoc(ref, sealVice()));
    await assertSucceeds(
      updateDoc(
        ref,
        sealVice({
          unitLabel: deleteField(),
          unitSingular: deleteField(),
          costPerUnit: deleteField(),
          currency: deleteField(),
        }),
      ),
    );
  });

  it('denies sealing that keeps any plaintext', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'vices/aliceVice'), { sealed: sealed(), unit: deleteField() }),
    );
    await assertFails(
      updateDoc(doc(asAlice(), 'vices/aliceVice'), { sealed: sealed(), name: deleteField() }),
    );
  });

  it('denies removing plaintext without adding sealed', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'vices/aliceVice'), { name: deleteField(), unit: deleteField() }),
    );
    await assertFails(
      updateDoc(doc(asAlice(), 'activities/aliceActivity'), { quantity: deleteField() }),
    );
  });

  it('denies a sealed value that is not bytes', async () => {
    await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), sealVice({ sealed: 'AQID' })));
  });

  it('denies changing a structural field while sealing', async () => {
    const vices = [
      { ownerID: BOB },
      { createdAt: Timestamp.fromDate(new Date('2025-01-01T00:00:00Z')) },
      { note: 'x' },
    ];
    for (const extra of vices) {
      await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), sealVice(extra)));
    }
  });

  it('denies removing sealed once it is there', async () => {
    const ref = doc(asAlice(), 'vices/aliceVice');
    await assertSucceeds(updateDoc(ref, sealVice()));
    await assertFails(updateDoc(ref, { sealed: deleteField() }));
    await assertFails(updateDoc(ref, { sealed: deleteField(), name: 'Tea', unit: 'drink' }));
  });

  it("denies sealing another user's documents", async () => {
    await assertFails(updateDoc(doc(asAlice(), 'vices/bobVice'), sealVice()));
    await assertFails(updateDoc(doc(asGuest(), 'vices/aliceVice'), sealVice()));
  });
});

// New documents may hold their content in one `sealed` envelope instead
// (lib/data/sealed.dart); the structural fields stay plaintext. An envelope is
// bytes: 29 bytes of version, nonce and tag around a padded plaintext of at
// most 4096 (lib/crypto/sealer.dart).
describe('sealed documents', () => {
  const resealed = bytesOf(29 + 256, 2);
  const sealedVice = (overrides = {}) => ({
    sealed: envelope,
    ownerID: ALICE,
    createdAt: serverTimestamp(),
    archived: false,
    ...overrides,
  });
  const sealedActivity = (overrides = {}) => ({
    sealed: envelope,
    quantity: 1,
    createdAt: new Date('2026-01-02T08:30:00Z'),
    ownerID: ALICE,
    viceID: 'aliceVice',
    ...overrides,
  });

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, 'vices/aliceSealedVice'), sealedVice({ createdAt }));
      await setDoc(doc(db, 'activities/aliceSealedActivity'), sealedActivity({ createdAt }));
    });
  });

  describe('vices', () => {
    it('creates a sealed vice', async () => {
      await assertSucceeds(setDoc(doc(asAlice(), 'vices/new'), sealedVice()));
    });

    it('refuses a plaintext vice', async () => {
      await assertFails(setDoc(doc(asAlice(), 'vices/new'), vice()));
    });

    it('refuses a sealed vice that also carries a plaintext name or unit', async () => {
      await assertFails(setDoc(doc(asAlice(), 'vices/new'), sealedVice({ name: 'Coffee' })));
      await assertFails(setDoc(doc(asAlice(), 'vices/new'), sealedVice({ unit: 'drink' })));
    });

    it('refuses a sealed vice that carries a plaintext unit label or price', async () => {
      for (const extra of [{ unitLabel: 'cups' }, { unitSingular: 'cup' }, { costPerUnit: 4.5 }, { currency: 'GBP' }]) {
        await assertFails(setDoc(doc(asAlice(), 'vices/new'), sealedVice(extra)));
      }
    });

    it('refuses a sealed vice without its structural fields', async () => {
      for (const field of ['ownerID', 'createdAt', 'archived']) {
        await assertFails(setDoc(doc(asAlice(), 'vices/new'), without(sealedVice(), field)));
      }
    });

    it('refuses a short, oversized or non-bytes envelope', async () => {
      await assertFails(setDoc(doc(asAlice(), 'vices/new'), sealedVice({ sealed: bytesOf(29) })));
      await assertFails(setDoc(doc(asAlice(), 'vices/new'), sealedVice({ sealed: bytesOf(29 + 4097) })));
      await assertFails(setDoc(doc(asAlice(), 'vices/new'), sealedVice({ sealed: 'A'.repeat(120) })));
      await assertFails(setDoc(doc(asAlice(), 'vices/new'), sealedVice({ sealed: 7 })));
      await assertSucceeds(setDoc(doc(asAlice(), 'vices/new'), sealedVice({ sealed: bytesOf(29 + 4096) })));
    });

    it('refuses a sealed vice for another owner', async () => {
      await assertFails(setDoc(doc(asAlice(), 'vices/new'), sealedVice({ ownerID: BOB })));
    });

    it('reseals and archives a sealed vice', async () => {
      const db = asAlice();
      await assertSucceeds(updateDoc(doc(db, 'vices/aliceSealedVice'), { sealed: resealed }));
      await assertSucceeds(updateDoc(doc(db, 'vices/aliceSealedVice'), { archived: true }));
    });

    it('refuses removing the envelope or adding plaintext beside it', async () => {
      const db = asAlice();
      await assertFails(updateDoc(doc(db, 'vices/aliceSealedVice'), { sealed: deleteField() }));
      await assertFails(updateDoc(doc(db, 'vices/aliceSealedVice'), { name: 'Coffee' }));
      await assertFails(updateDoc(doc(db, 'vices/aliceSealedVice'), { sealed: bytesOf(29 + 4097) }));
    });

    it('converts a plaintext vice by sealing it and removing its name, unit and category', async () => {
      await assertSucceeds(
        updateDoc(doc(asAlice(), 'vices/aliceVice'), {
          sealed: envelope,
          name: deleteField(),
          unit: deleteField(),
          category: deleteField(),
        }),
      );
    });

    it('converts a legacy vice whose unit is outside the enum', async () => {
      await assertSucceeds(
        updateDoc(doc(asAlice(), 'vices/aliceUnknownUnitVice'), {
          sealed: envelope,
          name: deleteField(),
          unit: deleteField(),
          category: deleteField(),
        }),
      );
    });

    it('refuses removing a plaintext name without sealing', async () => {
      await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), { name: deleteField() }));
    });

    it('refuses sealing a plaintext vice that keeps its name', async () => {
      await assertFails(
        updateDoc(doc(asAlice(), 'vices/aliceVice'), { sealed: envelope, unit: deleteField() }),
      );
    });

    it('seals a vice category with the name and unit', async () => {
      await assertFails(
        setDoc(doc(asAlice(), 'vices/new'), sealedVice({ category: 'caffeine' })),
      );
      await assertFails(
        updateDoc(doc(asAlice(), 'vices/aliceSealedVice'), { category: 'caffeine' }),
      );
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(
          doc(context.firestore(), 'vices/aliceCategoryVice'),
          vice({ category: 'caffeine' }),
        );
      });
      await assertFails(
        updateDoc(doc(asAlice(), 'vices/aliceCategoryVice'), {
          sealed: envelope,
          name: deleteField(),
          unit: deleteField(),
        }),
      );
      await assertFails(
        updateDoc(doc(asAlice(), 'vices/aliceCategoryVice'), { category: deleteField() }),
      );
      await assertSucceeds(
        updateDoc(doc(asAlice(), 'vices/aliceCategoryVice'), {
          sealed: envelope,
          name: deleteField(),
          unit: deleteField(),
          category: deleteField(),
        }),
      );
    });

    it("refuses Bob's reads and writes of Alice's sealed vice", async () => {
      await assertFails(getDoc(doc(asBob(), 'vices/aliceSealedVice')));
      await assertFails(updateDoc(doc(asBob(), 'vices/aliceSealedVice'), { sealed: resealed }));
    });
  });

  // The quantity and amount stay plaintext beside the envelope (Jack, 2026-11-06).
  describe('activities', () => {
    it('creates an activity with an envelope beside its plaintext quantity', async () => {
      const db = asAlice();
      await assertSucceeds(setDoc(doc(db, 'activities/new'), sealedActivity()));
      await assertSucceeds(
        setDoc(doc(db, 'activities/new2'), sealedActivity({ viceID: 'aliceSealedVice' })),
      );
    });

    it('refuses a plaintext activity', async () => {
      await assertFails(setDoc(doc(asAlice(), 'activities/new'), activity()));
    });

    it("refuses an activity on a vice the writer doesn't own or that is gone", async () => {
      await assertFails(setDoc(doc(asAlice(), 'activities/new'), sealedActivity({ viceID: 'bobVice' })));
      await assertFails(setDoc(doc(asAlice(), 'activities/new'), sealedActivity({ viceID: 'gone' })));
    });

    it('refuses a sealed activity without its quantity or structural fields', async () => {
      for (const field of ['quantity', 'viceID', 'ownerID', 'createdAt']) {
        await assertFails(setDoc(doc(asAlice(), 'activities/new'), without(sealedActivity(), field)));
      }
    });

    it('refuses an oversized or non-bytes envelope', async () => {
      await assertFails(
        setDoc(doc(asAlice(), 'activities/new'), sealedActivity({ sealed: bytesOf(29 + 4097) })),
      );
      await assertFails(setDoc(doc(asAlice(), 'activities/new'), sealedActivity({ sealed: 'x' })));
    });

    it('reseals, requantifies and moves an activity with an envelope', async () => {
      const db = asAlice();
      await assertSucceeds(
        updateDoc(doc(db, 'activities/aliceSealedActivity'), {
          sealed: resealed,
          quantity: 3,
          createdAt: Timestamp.fromDate(new Date('2026-01-03T08:30:00Z')),
        }),
      );
    });

    it('refuses removing the envelope or the quantity', async () => {
      const db = asAlice();
      await assertFails(
        updateDoc(doc(db, 'activities/aliceSealedActivity'), { sealed: deleteField() }),
      );
      await assertFails(
        updateDoc(doc(db, 'activities/aliceSealedActivity'), { quantity: deleteField() }),
      );
    });

    it('keeps triggers inside the envelope', async () => {
      const db = asAlice();
      await assertFails(
        setDoc(doc(db, 'activities/new'), sealedActivity({ triggers: ['social'] })),
      );
      await assertSucceeds(
        setDoc(doc(db, 'activities/new'), sealedActivity({ amount: 1.5, quantity: 2 })),
      );
      await assertFails(
        updateDoc(doc(db, 'activities/aliceSealedActivity'), { triggers: ['social'] }),
      );
      await assertSucceeds(
        updateDoc(doc(db, 'activities/aliceSealedActivity'), { amount: 2.5, quantity: 3 }),
      );
    });

    it('converts an activity by sealing its triggers and removing them', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(
          doc(context.firestore(), 'activities/aliceTriggeredActivity'),
          activity({ triggers: ['social', 'Long day'] }),
        );
      });
      const ref = doc(asAlice(), 'activities/aliceTriggeredActivity');
      await assertFails(updateDoc(ref, { sealed: envelope }));
      await assertSucceeds(
        updateDoc(ref, { sealed: envelope, triggers: deleteField(), quantity: 2 }),
      );
      await assertFails(updateDoc(ref, { triggers: ['social'] }));
      await assertSucceeds(updateDoc(ref, { sealed: resealed }));
    });

    it("refuses Bob's reads of Alice's sealed activity", async () => {
      await assertFails(getDoc(doc(asBob(), 'activities/aliceSealedActivity')));
    });

    it('counts sealed and plaintext activities together', async () => {
      const snapshot = await assertSucceeds(
        getCountFromServer(
          query(
            collection(asAlice(), 'activities'),
            where('viceID', '==', 'aliceVice'),
            where('ownerID', '==', ALICE),
          ),
        ),
      );
      assert.equal(snapshot.data().count, 4);
    });
  });
});

describe('summaries', () => {
  const summary = {
    computedAt: createdAt,
    windowDays: 90,
    vices: { aliceVice: { typical: 2, count: 14 } },
  };

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, `summaries/${ALICE}`), summary);
      await setDoc(doc(db, `summaries/${BOB}`), { ...summary, vices: {} });
    });
  });

  it('lets the owner read their summary', async () => {
    const snapshot = await assertSucceeds(getDoc(doc(asAlice(), `summaries/${ALICE}`)));
    assert.equal(snapshot.get('vices.aliceVice.typical'), 2);
  });

  it('lets the owner read a summary not yet written', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await deleteDoc(doc(context.firestore(), `summaries/${ALICE}`));
    });
    const snapshot = await assertSucceeds(getDoc(doc(asAlice(), `summaries/${ALICE}`)));
    assert.equal(snapshot.exists(), false);
  });

  it('denies reading another user\'s summary, signed in or not', async () => {
    await assertFails(getDoc(doc(asAlice(), `summaries/${BOB}`)));
    await assertFails(getDoc(doc(asGuest(), `summaries/${ALICE}`)));
  });

  it('denies listing summaries', async () => {
    await assertFails(getDocs(collection(asAlice(), 'summaries')));
  });

  it('denies the owner creating, changing or deleting their summary', async () => {
    const db = asAlice();
    await assertFails(updateDoc(doc(db, `summaries/${ALICE}`), { 'vices.aliceVice.typical': 9 }));
    await assertFails(setDoc(doc(db, `summaries/${ALICE}`), summary));
    await assertFails(deleteDoc(doc(db, `summaries/${ALICE}`)));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await deleteDoc(doc(context.firestore(), `summaries/${ALICE}`));
    });
    await assertFails(setDoc(doc(db, `summaries/${ALICE}`), summary));
  });
});

describe('cleanup', () => {
  const state = { candidates: [ALICE], scannedAt: createdAt };

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'cleanup/state'), state);
    });
  });

  it('denies every client reading or listing it, signed in or not', async () => {
    for (const db of [asAlice(), asGuest()]) {
      await assertFails(getDoc(doc(db, 'cleanup/state')));
      await assertFails(getDocs(collection(db, 'cleanup')));
    }
  });

  it('denies every client creating, changing or deleting it', async () => {
    for (const db of [asAlice(), asGuest()]) {
      await assertFails(setDoc(doc(db, 'cleanup/state'), { candidates: [], scannedAt: createdAt }));
      await assertFails(updateDoc(doc(db, 'cleanup/state'), { candidates: [] }));
      await assertFails(deleteDoc(doc(db, 'cleanup/state')));
      await assertFails(setDoc(doc(db, 'cleanup/other'), state));
    }
  });
});

describe('keys', () => {
  const record = (overrides = {}) => ({
    keyID: 'AAAAAAAAAAAAAAAAAAAAAA==',
    wrapped: Bytes.fromUint8Array(new Uint8Array(61)),
    createdAt,
    saved: false,
    cardDismissed: false,
    ...overrides,
  });

  it('lets the owner create, read, flag, replace and delete their record', async () => {
    const db = asAlice();
    const ref = doc(db, `keys/${ALICE}`);
    await assertSucceeds(setDoc(ref, record()));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(updateDoc(ref, { saved: true }));
    await assertSucceeds(updateDoc(ref, { cardDismissed: true }));
    await assertSucceeds(setDoc(ref, record({ keyID: 'BBBBBBBBBBBBBBBBBBBBBB==' })));
    await assertSucceeds(deleteDoc(ref));
  });

  it('denies another user, signed in or not, any access', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `keys/${ALICE}`), record());
    });
    await assertFails(getDoc(doc(asBob(), `keys/${ALICE}`)));
    await assertFails(getDoc(doc(asGuest(), `keys/${ALICE}`)));
    await assertFails(updateDoc(doc(asBob(), `keys/${ALICE}`), { saved: true }));
    await assertFails(deleteDoc(doc(asBob(), `keys/${ALICE}`)));
    await assertFails(setDoc(doc(asBob(), `keys/${ALICE}`), record()));
    await assertFails(getDocs(collection(asAlice(), 'keys')));
  });

  it('denies a record with a missing, extra or mistyped field', async () => {
    const ref = doc(asAlice(), `keys/${ALICE}`);
    const { saved, ...withoutSaved } = record();
    await assertFails(setDoc(ref, withoutSaved));
    await assertFails(setDoc(ref, record({ key: 'the raw key' })));
    await assertFails(setDoc(ref, record({ keyID: 'short' })));
    await assertFails(setDoc(ref, record({ wrapped: Bytes.fromUint8Array(new Uint8Array(32)) })));
    await assertFails(setDoc(ref, record({ wrapped: 'not bytes' })));
    await assertFails(setDoc(ref, record({ createdAt: 'yesterday' })));
    await assertFails(setDoc(ref, record({ saved: 'yes' })));
  });

  it('denies an update that removes a field or adds one', async () => {
    const ref = doc(asAlice(), `keys/${ALICE}`);
    await assertSucceeds(setDoc(ref, record()));
    await assertFails(updateDoc(ref, { wrapped: deleteField() }));
    await assertFails(updateDoc(ref, { note: 'x' }));
  });
});

// Account.startAsGuest: an anonymous Firebase Auth user has a uid like any
// other, and the ownerID checks apply to it unchanged.
describe('a guest signed in anonymously', () => {
  const GUEST = 'guest';
  const asAnonymous = () =>
    testEnv
      .authenticatedContext(GUEST, { firebase: { sign_in_provider: 'anonymous' } })
      .firestore();

  it('creates, reads, edits and deletes its own vice and activity', async () => {
    const db = asAnonymous();
    await assertSucceeds(setDoc(doc(db, 'vices/guestVice'), newVice({ ownerID: GUEST })));
    await assertSucceeds(
      setDoc(
        doc(db, 'activities/guestActivity'),
        newActivity({ ownerID: GUEST, viceID: 'guestVice' }),
      ),
    );
    const mine = await assertSucceeds(
      getDocs(query(collection(db, 'activities'), where('ownerID', '==', GUEST))),
    );
    assert.deepEqual(mine.docs.map((d) => d.id), ['guestActivity']);
    await assertSucceeds(updateDoc(doc(db, 'activities/guestActivity'), { quantity: 3 }));
    await assertSucceeds(deleteDoc(doc(db, 'activities/guestActivity')));
    await assertSucceeds(deleteDoc(doc(db, 'vices/guestVice')));
  });

  it('cannot write as another owner or read another owner\'s data', async () => {
    const db = asAnonymous();
    await assertFails(addDoc(collection(db, 'vices'), newVice()));
    await assertFails(getDoc(doc(db, 'vices/aliceVice')));
    await assertFails(
      getDocs(query(collection(db, 'activities'), where('ownerID', '==', ALICE))),
    );
  });

  it('keeps its data once linked, since linking keeps the uid', async () => {
    await assertSucceeds(
      setDoc(doc(asAnonymous(), 'vices/guestVice'), newVice({ ownerID: GUEST })),
    );
    const linked = testEnv
      .authenticatedContext(GUEST, {
        email: 'sam@example.com',
        firebase: { sign_in_provider: 'password' },
      })
      .firestore();
    await assertSucceeds(getDoc(doc(linked, 'vices/guestVice')));
  });
});
