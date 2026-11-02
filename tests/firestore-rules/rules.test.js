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
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
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
    await setDoc(doc(db, 'vices/bobVice'), vice({ ownerID: BOB, createdAt }));
    await setDoc(doc(db, 'activities/aliceActivity'), activity({ createdAt }));
    await setDoc(doc(db, 'activities/aliceLegacyActivity'), {
      ...activity({ createdAt }),
      note: 'written from the console',
    });
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
    });

    it('denies a non-owner delete', async () => {
      await assertFails(deleteDoc(doc(asBob(), 'vices/aliceVice')));
    });

    it('denies an unauthenticated delete', async () => {
      await assertFails(deleteDoc(doc(asGuest(), 'vices/aliceVice')));
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

    it('allows a negative or zero quantity, which the dialog accepts', async () => {
      await assertSucceeds(addDoc(collection(asAlice(), 'activities'), activity({ quantity: 0 })));
      await assertSucceeds(addDoc(collection(asAlice(), 'activities'), activity({ quantity: -1 })));
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
  });

  describe('read', () => {
    it('allows the owner to get their activity', async () => {
      await assertSucceeds(getDoc(doc(asAlice(), 'activities/aliceActivity')));
    });

    it('allows the activity list query', async () => {
      await assertSucceeds(
        getDocs(
          query(
            collection(asAlice(), 'activities'),
            where('viceID', 'in', ['aliceVice', 'aliceLegacyVice']),
            where('ownerID', '==', ALICE),
            orderBy('createdAt', 'desc'),
          ),
        ),
      );
    });

    it('allows the day-window query', async () => {
      await assertSucceeds(
        getDocs(
          query(
            collection(asAlice(), 'activities'),
            where('viceID', 'in', ['aliceVice']),
            where('ownerID', '==', ALICE),
            where('createdAt', '>=', Timestamp.fromDate(new Date('2026-01-01T00:00:00Z'))),
            where('createdAt', '<', Timestamp.fromDate(new Date('2026-01-02T00:00:00Z'))),
            orderBy('createdAt', 'desc'),
          ),
        ),
      );
    });

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

    it('allows editing a legacy activity carrying an extra field', async () => {
      await assertSucceeds(
        updateDoc(doc(asAlice(), 'activities/aliceLegacyActivity'), { quantity: 3 }),
      );
    });

    it('denies wrong types', async () => {
      const ref = doc(asAlice(), 'activities/aliceActivity');
      await assertFails(updateDoc(ref, { quantity: '3' }));
      await assertFails(updateDoc(ref, { quantity: 1.5 }));
      await assertFails(updateDoc(ref, { createdAt: 'yesterday' }));
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
    });

    it('denies a non-owner delete', async () => {
      await assertFails(deleteDoc(doc(asBob(), 'activities/aliceActivity')));
    });

    it('denies an unauthenticated delete', async () => {
      await assertFails(deleteDoc(doc(asGuest(), 'activities/aliceActivity')));
    });
  });
});
