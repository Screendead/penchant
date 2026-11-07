import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  addDoc,
  collection,
  deleteDoc,
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
  ...overrides,
});

const activity = (overrides = {}) => ({
  createdAt: new Date('2026-01-02T08:30:00Z'),
  ownerID: ALICE,
  quantity: 2,
  viceID: 'aliceVice',
  ...overrides,
});

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
    it('allows the shape add_vice.dart writes, with a server timestamp', async () => {
      await assertSucceeds(addDoc(collection(asAlice(), 'vices'), vice()));
    });

    it('allows every unit in the Unit enum', async () => {
      for (const unit of ['item', 'time', 'puff', 'drink', 'minute', 'hour']) {
        await assertSucceeds(addDoc(collection(asAlice(), 'vices'), vice({ unit })));
      }
    });

    it('denies creating a vice owned by someone else', async () => {
      await assertFails(addDoc(collection(asAlice(), 'vices'), vice({ ownerID: BOB })));
    });

    it('denies unauthenticated creates', async () => {
      await assertFails(addDoc(collection(asGuest(), 'vices'), vice()));
    });

    it('denies a missing required field', async () => {
      for (const key of ['name', 'unit', 'ownerID', 'createdAt', 'archived']) {
        await assertFails(addDoc(collection(asAlice(), 'vices'), without(vice(), key)));
      }
    });

    it('denies an unknown field', async () => {
      await assertFails(addDoc(collection(asAlice(), 'vices'), vice({ colour: 'red' })));
    });

    it('allows a name of 60 characters and denies 61', async () => {
      await assertSucceeds(addDoc(collection(asAlice(), 'vices'), vice({ name: 'x'.repeat(60) })));
      await assertFails(addDoc(collection(asAlice(), 'vices'), vice({ name: 'x'.repeat(61) })));
    });

    // Pins the unit lib/data/limits.dart measures in: each emoji is two UTF-16 code units.
    it('counts the name in UTF-16 code units', async () => {
      await assertSucceeds(addDoc(collection(asAlice(), 'vices'), vice({ name: '😀'.repeat(30) })));
      await assertFails(addDoc(collection(asAlice(), 'vices'), vice({ name: '😀'.repeat(31) })));
    });

    it('denies wrong types and invalid values', async () => {
      const bad = [
        { name: 42 },
        { name: '' },
        { unit: 'pouch' },
        { unit: 3 },
        { createdAt: '2026-01-01' },
        { archived: 'false' },
        { ownerID: null },
      ];
      for (const overrides of bad) {
        await assertFails(addDoc(collection(asAlice(), 'vices'), vice(overrides)));
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

    it('denies renaming to more than 60 characters', async () => {
      await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), { name: 'x'.repeat(61) }));
      await assertFails(
        updateDoc(doc(asAlice(), 'vices/aliceLongNameVice'), { name: 'x'.repeat(62) }),
      );
    });

    it('denies a non-bool archived', async () => {
      await assertFails(updateDoc(doc(asAlice(), 'vices/aliceVice'), { archived: 'yes' }));
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
    it('allows the shape record_new_activity_dialog.dart writes with add()', async () => {
      await assertSucceeds(addDoc(collection(asAlice(), 'activities'), activity()));
    });

    it('allows the same shape written with doc().set()', async () => {
      await assertSucceeds(setDoc(doc(collection(asAlice(), 'activities')), activity()));
    });

    it('allows a quantity of 1', async () => {
      await assertSucceeds(addDoc(collection(asAlice(), 'activities'), activity({ quantity: 1 })));
    });

    it('denies a zero or negative quantity', async () => {
      await assertFails(addDoc(collection(asAlice(), 'activities'), activity({ quantity: 0 })));
      await assertFails(addDoc(collection(asAlice(), 'activities'), activity({ quantity: -1 })));
    });

    it("allows recording against the owner's legacy or archived vice", async () => {
      await assertSucceeds(
        addDoc(collection(asAlice(), 'activities'), activity({ viceID: 'aliceLegacyVice' })),
      );
      await assertSucceeds(updateDoc(doc(asAlice(), 'vices/aliceVice'), { archived: true }));
      await assertSucceeds(addDoc(collection(asAlice(), 'activities'), activity()));
    });

    it("denies recording against another user's vice", async () => {
      await assertFails(
        addDoc(collection(asAlice(), 'activities'), activity({ viceID: 'bobVice' })),
      );
    });

    it('denies recording against a vice that does not exist', async () => {
      for (const viceID of ['gone', '', 'aliceVice/activities/x']) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), activity({ viceID })));
      }
    });

    it('denies recording against a vice deleted earlier', async () => {
      await assertSucceeds(deleteDoc(doc(asAlice(), 'vices/aliceVice')));
      await assertFails(addDoc(collection(asAlice(), 'activities'), activity()));
    });

    // get() reads committed state; seeing the batch's own vice would need getAfter().
    it('denies a batch that creates the vice and its first activity together', async () => {
      const db = asAlice();
      const viceRef = doc(collection(db, 'vices'));
      const batch = writeBatch(db);
      batch.set(viceRef, vice());
      batch.set(doc(collection(db, 'activities')), activity({ viceID: viceRef.id }));
      await assertFails(batch.commit());
    });

    it('denies creating an activity owned by someone else', async () => {
      await assertFails(addDoc(collection(asAlice(), 'activities'), activity({ ownerID: BOB })));
    });

    it('denies unauthenticated creates', async () => {
      await assertFails(addDoc(collection(asGuest(), 'activities'), activity()));
    });

    it('denies a missing required field', async () => {
      for (const key of ['viceID', 'quantity', 'ownerID', 'createdAt']) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), without(activity(), key)));
      }
    });

    it('denies an unknown field', async () => {
      await assertFails(addDoc(collection(asAlice(), 'activities'), activity({ note: 'hi' })));
    });

    it('denies wrong types', async () => {
      const bad = [
        { quantity: 2.5 },
        { quantity: '2' },
        { viceID: 7 },
        { createdAt: '2026-01-02' },
      ];
      for (const overrides of bad) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), activity(overrides)));
      }
    });

    it('allows triggers: tree paths and free text, up to 10, each 1 to 60 long', async () => {
      const valid = [
        [],
        ['work/meeting'],
        ['feeling/stressed', 'Late train'],
        Array.from({ length: 10 }, (_, i) => `custom ${i}`),
        ['x'.repeat(60)],
      ];
      for (const triggers of valid) {
        await assertSucceeds(addDoc(collection(asAlice(), 'activities'), activity({ triggers })));
      }
    });

    it('denies more than 10 triggers, or one empty or over 60 long', async () => {
      const invalid = [
        Array.from({ length: 11 }, (_, i) => `t${i}`),
        [''],
        ['x'.repeat(61)],
        ['work', 'x'.repeat(61)],
        [...Array.from({ length: 9 }, (_, i) => `t${i}`), 'x'.repeat(61)],
      ];
      for (const triggers of invalid) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), activity({ triggers })));
      }
    });

    it('denies triggers of the wrong type', async () => {
      for (const triggers of ['work/meeting', 7, { work: true }, [7], ['work', null], [{ path: 'work' }]]) {
        await assertFails(addDoc(collection(asAlice(), 'activities'), activity({ triggers })));
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
      await assertSucceeds(setDoc(ref, activity()));
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
    await assertSucceeds(setDoc(doc(db, 'vices/guestVice'), vice({ ownerID: GUEST })));
    await assertSucceeds(
      setDoc(
        doc(db, 'activities/guestActivity'),
        activity({ ownerID: GUEST, viceID: 'guestVice' }),
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
    await assertFails(addDoc(collection(db, 'vices'), vice()));
    await assertFails(getDoc(doc(db, 'vices/aliceVice')));
    await assertFails(
      getDocs(query(collection(db, 'activities'), where('ownerID', '==', ALICE))),
    );
  });

  it('keeps its data once linked, since linking keeps the uid', async () => {
    await assertSucceeds(
      setDoc(doc(asAnonymous(), 'vices/guestVice'), vice({ ownerID: GUEST })),
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
