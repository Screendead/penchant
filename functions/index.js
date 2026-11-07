'use strict';

const { initializeApp } = require('firebase-admin/app');
const { FieldPath, Timestamp, getFirestore } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions');
const { onSchedule } = require('firebase-functions/v2/scheduler');

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
