'use strict';

// Admin getUsers takes at most 100 identifiers a call and rejects the whole
// call over one malformed uid, so only Auth-shaped uids are ever asked about.
const LOOKUP_BATCH = 100;
const MAX_UID_LENGTH = 128;
// A second run within this of the first (the scheduler can fire a job twice)
// is not the next day's run, so it never confirms a candidate.
const MIN_RUN_GAP_MS = 20 * 60 * 60 * 1000;
// Keeps the state document far below Firestore's 1 MiB; a missing uid past it
// is picked up once the ones before it are gone.
const MAX_CANDIDATES = 5000;

function validUid(uid) {
  return typeof uid === 'string' && uid.length > 0 && uid.length <= MAX_UID_LENGTH;
}

function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

// fetchPage(cursor) resolves to { uids, cursor, done }; cursor is null on the
// first call. Stops after maxPages, reporting the scan as truncated.
async function distinctOwners(fetchPage, maxPages) {
  const uids = new Set();
  let invalid = 0;
  let cursor = null;
  for (let pages = 0; pages < maxPages; pages++) {
    const page = await fetchPage(cursor);
    for (const uid of page.uids) {
      if (validUid(uid)) uids.add(uid);
      else invalid++;
    }
    if (page.done) return { uids, invalid, truncated: false };
    cursor = page.cursor;
  }
  return { uids, invalid, truncated: true };
}

// getUsers(identifiers) is Admin Auth's getUsers. A uid counts as missing only
// when Auth lists it in notFound and returns no user for it; any error
// propagates, so a failed lookup never reads as a missing account.
async function missingUids(getUsers, uids) {
  const missing = new Set();
  for (const batch of chunk([...uids].filter(validUid), LOOKUP_BATCH)) {
    const asked = new Set(batch);
    const result = await getUsers(batch.map((uid) => ({ uid })));
    const found = new Set(result.users.map((user) => user.uid));
    for (const { uid } of result.notFound) {
      if (asked.has(uid) && !found.has(uid)) missing.add(uid);
    }
  }
  return missing;
}

// previous is the stored state ({ candidates, scannedAt } or null). A uid is
// deleted only when the previous run, at least MIN_RUN_GAP_MS earlier, and this
// one both found it missing; a run too soon after the last keeps that state.
function reconcile(previous, missing, now) {
  const tooSoon = previous != null && now.getTime() - previous.scannedAt.getTime() < MIN_RUN_GAP_MS;
  if (tooSoon) return { toDelete: [], next: null };
  const before = new Set(previous ? previous.candidates : []);
  const toDelete = [...missing].filter((uid) => before.has(uid)).sort();
  return { toDelete, next: { candidates: [...missing].sort().slice(0, MAX_CANDIDATES), scannedAt: now } };
}

// io holds the Firestore and Auth calls (index.js); dryRun only counts and logs.
async function runCleanup(io, { dryRun, now, maxDeletes }) {
  const owners = new Set();
  const scanned = {};
  for (const [name, fetchPage, maxPages] of io.sources) {
    const { uids, invalid, truncated } = await distinctOwners(fetchPage, maxPages);
    for (const uid of uids) owners.add(uid);
    scanned[name] = { owners: uids.size, invalid, truncated };
  }

  const missing = await missingUids(io.getUsers, owners);
  const previous = await io.readState();
  const { toDelete, next } = reconcile(previous, missing, now);
  if (next == null) {
    io.log('warn', 'Orphan cleanup skipped: the last run was too recent', {
      lastRun: previous.scannedAt.toISOString(),
    });
    return { skipped: true, acted: [] };
  }

  const acting = toDelete.slice(0, maxDeletes);
  const acted = [];
  for (const uid of acting) {
    const counts = await io.countOwned(uid);
    if (dryRun) {
      io.log('info', 'Orphan cleanup would delete', { dryRun, uid, counts });
    } else {
      await io.deleteOwned(uid);
      io.log('info', 'Orphan cleanup deleted', { dryRun, uid, counts });
    }
    acted.push(uid);
  }

  await io.writeState(next);
  io.log('info', 'Orphan cleanup finished', {
    dryRun,
    owners: owners.size,
    scanned,
    missing: missing.size,
    confirmed: toDelete.length,
    deferred: toDelete.length - acting.length,
    candidates: next.candidates.length,
  });
  return { skipped: false, acted };
}

module.exports = {
  LOOKUP_BATCH,
  MAX_CANDIDATES,
  MIN_RUN_GAP_MS,
  chunk,
  distinctOwners,
  missingUids,
  reconcile,
  runCleanup,
  validUid,
};
