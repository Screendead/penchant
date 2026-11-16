'use strict';

const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { FieldPath, Timestamp, getFirestore } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions');
const { defineString } = require('firebase-functions/params');
const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const Anthropic = require('@anthropic-ai/sdk');
const { oidcFederationProvider } = require('@anthropic-ai/sdk/lib/credentials/oidc-federation');

const { OWNED_COLLECTIONS, runCleanup } = require('./cleanup.js');
const { summarise } = require('./summary.js');
const { DailyCap, readNote, validNote, wantsQuestion } = require('./note_reader.js');
const { validFigures, writeWeekly } = require('./weekly_words.js');
const { askJournal, validInput } = require('./ask_journal.js');
const { verifiedCaller } = require('./caller.js');
const letter = require('./letter.js');

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
      ...OWNED_COLLECTIONS.map((name) => [name, ownerScan(db, name), MAX_OWNERS_PER_COLLECTION]),
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
      const [counts, key, summary] = await Promise.all([
        Promise.all(OWNED_COLLECTIONS.map((name) => owned(name, uid).count().get())),
        db.collection('keys').doc(uid).get(),
        db.collection('summaries').doc(uid).get(),
      ]);
      return {
        ...Object.fromEntries(OWNED_COLLECTIONS.map((name, i) => [name, counts[i].data().count])),
        keys: key.exists ? 1 : 0,
        summaries: summary.exists ? 1 : 0,
      };
    },
    async deleteOwned(uid) {
      for (const name of OWNED_COLLECTIONS) {
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

// Workload identity federation with Anthropic: identifiers from the Claude
// Console, empty until set so that a deploy never prompts for them.
const federation = {
  federationRuleId: defineString('ANTHROPIC_FEDERATION_RULE_ID', { default: '' }),
  organizationId: defineString('ANTHROPIC_ORGANIZATION_ID', { default: '' }),
  serviceAccountId: defineString('ANTHROPIC_SERVICE_ACCOUNT_ID', { default: '' }),
  workspaceId: defineString('ANTHROPIC_WORKSPACE_ID', { default: '' }),
};

const IDENTITY_URL =
  'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity' +
  '?audience=https://api.anthropic.com&format=full';

// A fresh Google-signed token per exchange: Anthropic refuses a reused one.
async function googleIdentityToken() {
  const response = await fetch(IDENTITY_URL, { headers: { 'Metadata-Flavor': 'Google' } });
  if (!response.ok) throw new Error(`metadata server answered ${response.status}`);
  return response.text();
}

const clients = new Map();
// [timeout] in milliseconds; one client per timeout.
function anthropicClient(timeout = 8000) {
  if (clients.has(timeout)) return clients.get(timeout);
  const ids = Object.fromEntries(Object.entries(federation).map(([key, param]) => [key, param.value()]));
  if (Object.values(ids).some((value) => value === '')) return null;
  const anthropic = new Anthropic({
    credentials: oidcFederationProvider({
      identityTokenProvider: googleIdentityToken,
      ...ids,
      baseURL: 'https://api.anthropic.com',
      fetch,
    }),
    // Inside the app's wait (10 s, or the letter's 240 s), with no retry.
    timeout,
    maxRetries: 0,
  });
  clients.set(timeout, anthropic);
  return anthropic;
}

const CALLABLE = {
  serviceAccount: 'note-reader@screendead-vice-tracker.iam.gserviceaccount.com',
  maxInstances: 2,
  timeoutSeconds: 15,
  memory: '256MiB',
};

const noteCap = new DailyCap();
const askCap = new DailyCap(60);
const weeklyCap = new DailyCap(10);
const letterCap = new DailyCap(3);

// The letter's reply takes one to two minutes: the SDK gives up inside the
// function's timeout, which ends inside the app's 240 s wait.
const LETTER_SDK_TIMEOUT_MS = 200000;
const LETTER_CALLABLE = { ...CALLABLE, timeoutSeconds: 220, memory: '512MiB' };

// The client, or failed-precondition while the federation is not set up.
function configuredClient(name, timeout) {
  const client = anthropicClient(timeout);
  if (client == null) {
    logger.warn(name, { reason: 'not_configured' });
    throw new HttpsError('failed-precondition', 'This is not set up yet.');
  }
  return client;
}

// Guests and unverified emails may not use Claude; checked before the cap and
// any model call.
function requireVerified(name, auth) {
  if (!verifiedCaller(auth)) {
    logger.warn(name, { reason: 'unverified' });
    throw new HttpsError('permission-denied', 'Verify an email address to use this.');
  }
}

function takeCap(name, cap, uid) {
  if (!cap.take(uid)) {
    logger.warn(name, { reason: 'daily_cap' });
    throw new HttpsError('resource-exhausted', 'Enough for today.');
  }
}

// Suggests starter-tree tags for one journal note, and with `question: true` a
// follow-up question. Logs counts and reason codes only: never the uid, the
// note, a quote or the model's output. A question's drop reason can carry a
// matched term after a colon, so only the part before it is logged.
exports.readNote = onCall(CALLABLE, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to read a note.');
  requireVerified('readNote', request.auth);
  const note = validNote(request.data);
  if (note == null) throw new HttpsError('invalid-argument', 'A note is 1 to 2000 characters.');
  const client = configuredClient('readNote');
  takeCap('readNote', noteCap, request.auth.uid);
  const asked = wantsQuestion(request.data);
  const { tags, dropped, reason, question, questionDrop } = await readNote(client, note, { question: asked });
  const fields = { reason, tags: tags.length, dropped };
  if (asked) {
    fields.question = question != null;
    if (typeof questionDrop === 'string') fields.questionDrop = questionDrop.split(':')[0];
  }
  logger.info('readNote', fields);
  return asked ? { tags, reason, question } : { tags, reason };
});

// One paragraph in words over a week's figures. Logs the reason code only:
// never the uid, the figures or the paragraph.
exports.writeWeekly = onCall(CALLABLE, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to write a weekly review.');
  requireVerified('writeWeekly', request.auth);
  const figures = validFigures(request.data);
  if (figures == null) throw new HttpsError('invalid-argument', 'The figures are not in the expected form.');
  const client = configuredClient('writeWeekly');
  takeCap('writeWeekly', weeklyCap, request.auth.uid);
  const { text, reason } = await writeWeekly(client, figures);
  logger.info('writeWeekly', { reason });
  return { text, reason };
});

// A question about the journal turned into SQL the device runs. Logs the
// reason code only: never the uid, the question, the habits or the answer.
// Its own timeout, above askJournal's 40 s request timeout.
exports.askJournal = onCall({ ...CALLABLE, timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to ask your journal.');
  requireVerified('askJournal', request.auth);
  const input = validInput(request.data);
  if (input == null) throw new HttpsError('invalid-argument', 'The question is not in the expected form.');
  const client = configuredClient('askJournal');
  takeCap('askJournal', askCap, request.auth.uid);
  const { answer, reason } = await askJournal(client, input);
  logger.info('askJournal', { reason });
  return { answer, reason };
});

// A review of a chosen period of the journal, as the device built and showed
// it. Logs the reason code and how many passages were withheld, each reason
// only up to any colon: never the uid, the journal or the letter.
exports.writeLetter = onCall(LETTER_CALLABLE, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to ask for a letter.');
  requireVerified('writeLetter', request.auth);
  const input = letter.validInput(request.data);
  if (input == null) throw new HttpsError('invalid-argument', 'The journal is not in the expected form.');
  const client = configuredClient('writeLetter', LETTER_SDK_TIMEOUT_MS);
  takeCap('writeLetter', letterCap, request.auth.uid);
  const { letter: written, reason, withheld } = await letter.writeLetter(client, input);
  logger.info('writeLetter', { reason, withheld: withheld.map((w) => w.reason.split(':')[0]) });
  return { letter: written, reason };
});
