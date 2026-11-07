'use strict';

const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { FieldPath, Timestamp, getFirestore } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions');
const { onSchedule } = require('firebase-functions/v2/scheduler');

const { runCleanup } = require('./cleanup.js');
const { summarise } = require('./summary.js');

initializeApp();

const WINDOW_DAYS = 90;
const PAGE = 500;
// 20,000 entries a user in 90 days; past it the summary covers the newest.
const MAX_PAGES_PER_USER = 40;
const BATCH = 400;

// Every user with at least one habit, read as ownerID alone.
async function owners(db) {
  const uids = new Set();
  let last = null;
  for (;;) {
    let q = db.collection('vices').orderBy(FieldPath.documentId()).select('ownerID').limit(PAGE);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    for (const doc of page.docs) {
      const uid = doc.get('ownerID');
      if (typeof uid === 'string' && uid !== '') uids.add(uid);
    }
    if (page.size < PAGE) return uids;
    last = page.docs[page.size - 1];
  }
}

// One query a user over the window, paged on the activities (ownerID asc,
// createdAt desc) index the app's day query already uses.
async function recentActivities(db, uid, since) {
  const rows = [];
  let last = null;
  for (let pages = 0; pages < MAX_PAGES_PER_USER; pages++) {
    let q = db
      .collection('activities')
      .where('ownerID', '==', uid)
      .where('createdAt', '>=', since)
      .orderBy('createdAt', 'desc')
      .select('viceID', 'quantity')
      .limit(PAGE);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    for (const doc of page.docs) {
      rows.push({ viceID: doc.get('viceID'), quantity: doc.get('quantity') });
    }
    if (page.size < PAGE) return { rows, truncated: false };
    last = page.docs[page.size - 1];
  }
  return { rows, truncated: true };
}

async function refreshSummaries(db, now = new Date()) {
  const since = Timestamp.fromMillis(now.getTime() - WINDOW_DAYS * 24 * 60 * 60 * 1000);
  const computedAt = Timestamp.fromDate(now);
  const uids = await owners(db);

  let batch = db.batch();
  let pending = 0;
  const flush = async () => {
    if (pending > 0) await batch.commit();
    batch = db.batch();
    pending = 0;
  };

  for (const uid of uids) {
    const { rows, truncated } = await recentActivities(db, uid, since);
    if (truncated) logger.warn('Summary covers only the newest entries', { uid, entries: rows.length });
    batch.set(db.collection('summaries').doc(uid), {
      computedAt,
      windowDays: WINDOW_DAYS,
      vices: summarise(rows),
    });
    if (++pending >= BATCH) await flush();
  }

  // A user with no habits left, or a deleted account, keeps no summary.
  let removed = 0;
  for (const ref of await db.collection('summaries').listDocuments()) {
    if (!uids.has(ref.id)) {
      batch.delete(ref);
      removed++;
      if (++pending >= BATCH) await flush();
    }
  }
  await flush();
  logger.info('Summaries refreshed', { users: uids.size, removed });
}

exports.refreshSummaries = refreshSummaries;

exports.monthlySummaries = onSchedule(
  {
    schedule: '0 3 1 * *',
    timeZone: 'Etc/UTC',
    retryCount: 1,
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async () => {
    await refreshSummaries(getFirestore());
  },
);

// Dry run: the job only counts and logs. Setting this true is the reviewed
// change that lets it delete.
const DELETE_ORPHANED_DATA = false;
// One query an owner per collection, run in sequence, within the 540 s timeout.
const MAX_OWNERS_PER_COLLECTION = 5000;
const MAX_ID_PAGES = 100;
const MAX_DELETES_PER_RUN = 50;
// 40,000 documents a collection an owner; past it the next run carries on.
const MAX_DELETE_PAGES = 100;

// Each page jumps past the last owner seen, so a collection costs one read per
// distinct owner rather than one per document. Strings sort together in
// Firestore's value type ordering, so the scan starts at '' and ends at the
// first value that is not one.
function ownerScan(db, name) {
  return async (cursor) => {
    const page = await db
      .collection(name)
      .where('ownerID', cursor == null ? '>=' : '>', cursor ?? '')
      .orderBy('ownerID')
      .select('ownerID')
      .limit(1)
      .get();
    if (page.empty) return { uids: [], cursor, done: true };
    const uid = page.docs[0].get('ownerID');
    if (typeof uid !== 'string') return { uids: [], cursor, done: true };
    return { uids: [uid], cursor: uid, done: false };
  };
}

// Collections keyed by uid, read as ids alone.
function idScan(db, name) {
  return async (cursor) => {
    let q = db.collection(name).orderBy(FieldPath.documentId()).select().limit(PAGE);
    if (cursor) q = q.startAfter(cursor);
    const page = await q.get();
    return {
      uids: page.docs.map((doc) => doc.id),
      cursor: page.empty ? cursor : page.docs[page.size - 1],
      done: page.size < PAGE,
    };
  };
}

function cleanupIO(db, auth) {
  const state = db.collection('cleanup').doc('state');
  const owned = (name, uid) => db.collection(name).where('ownerID', '==', uid);
  return {
    sources: [
      ['vices', ownerScan(db, 'vices'), MAX_OWNERS_PER_COLLECTION],
      ['activities', ownerScan(db, 'activities'), MAX_OWNERS_PER_COLLECTION],
      ['keys', idScan(db, 'keys'), MAX_ID_PAGES],
      ['summaries', idScan(db, 'summaries'), MAX_ID_PAGES],
    ],
    getUsers: (identifiers) => auth.getUsers(identifiers),
    async readState() {
      const snapshot = await state.get();
      const candidates = snapshot.get('candidates');
      const scannedAt = snapshot.get('scannedAt');
      if (!Array.isArray(candidates) || !(scannedAt instanceof Timestamp)) return null;
      return { candidates, scannedAt: scannedAt.toDate() };
    },
    async writeState({ candidates, scannedAt }) {
      await state.set({ candidates, scannedAt: Timestamp.fromDate(scannedAt) });
    },
    async countOwned(uid) {
      const [vices, activities, key, summary] = await Promise.all([
        owned('vices', uid).count().get(),
        owned('activities', uid).count().get(),
        db.collection('keys').doc(uid).get(),
        db.collection('summaries').doc(uid).get(),
      ]);
      return {
        vices: vices.data().count,
        activities: activities.data().count,
        keys: key.exists ? 1 : 0,
        summaries: summary.exists ? 1 : 0,
      };
    },
    async deleteOwned(uid) {
      for (const name of ['activities', 'vices']) {
        for (let pages = 0; pages < MAX_DELETE_PAGES; pages++) {
          const page = await owned(name, uid).select().limit(BATCH).get();
          if (page.empty) break;
          const batch = db.batch();
          for (const doc of page.docs) batch.delete(doc.ref);
          await batch.commit();
        }
      }
      const batch = db.batch();
      batch.delete(db.collection('keys').doc(uid));
      batch.delete(db.collection('summaries').doc(uid));
      await batch.commit();
    },
    log: (level, message, fields) => logger[level](message, fields),
  };
}

// Firebase's anonymous-account clean-up deletes guest Auth users after 30 days
// and leaves their Firestore documents behind.
exports.dailyOrphanCleanup = onSchedule(
  {
    schedule: '30 4 * * *',
    timeZone: 'Etc/UTC',
    retryCount: 1,
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async () => {
    await runCleanup(cleanupIO(getFirestore(), getAuth()), {
      dryRun: !DELETE_ORPHANED_DATA,
      now: new Date(),
      maxDeletes: MAX_DELETES_PER_RUN,
    });
  },
);
